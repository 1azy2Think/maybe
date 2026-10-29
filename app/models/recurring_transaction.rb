class RecurringTransaction < ApplicationRecord
  include Monetizable

  monetize :amount

  belongs_to :family
  belongs_to :account
  belongs_to :destination_account, class_name: "Account", optional: true
  belongs_to :category, optional: true

  has_many :transactions, dependent: :nullify

  enum :kind, { expense: "expense", income: "income", transfer: "transfer" }, validate: true
  enum :frequency, { weekly: "weekly", biweekly: "biweekly", monthly: "monthly", yearly: "yearly" }, validate: true

  validates :amount, numericality: { greater_than: 0 }
  validates :start_date, presence: true
  validates :name, presence: true, unless: :transfer?
  validates :destination_account, presence: true, if: :transfer?
  validate :associations_belong_to_family
  validate :transfer_has_different_accounts
  validate :end_date_on_or_after_start_date

  before_validation :clear_fields_for_kind
  before_validation :set_currency
  before_save :reschedule, if: :schedule_changed?
  before_save :skip_missed_occurrences, if: -> { persisted? && will_save_change_to_active?(from: false, to: true) }

  scope :due, ->(as_of = Date.current) { where(active: true).where(next_occurrence_date: ..as_of) }
  scope :by_next_occurrence, -> { order(active: :desc, next_occurrence_date: :asc) }

  # Posts every occurrence that has come due (catching up any missed dates).
  # Each occurrence is posted under a row lock, so concurrent or repeated runs never double-post.
  def post_due!(as_of: Date.current)
    posted_dates = []

    loop do
      date = post_next_occurrence!(as_of)
      break unless date
      posted_dates << date
    end

    # Transfer::Creator schedules its own account syncs
    account.sync_later(window_start_date: posted_dates.min) if posted_dates.any? && !transfer?

    posted_dates
  end

  def occurrence_date(index)
    case frequency
    when "weekly" then start_date.advance(weeks: index)
    when "biweekly" then start_date.advance(weeks: index * 2)
    when "monthly" then start_date.advance(months: index)
    when "yearly" then start_date.advance(years: index)
    end
  end

  def display_name
    return name unless transfer?

    prefix = destination_account&.liability? ? "Payment" : "Transfer"
    "#{prefix} to #{destination_account&.name}"
  end

  def ended?
    end_date.present? && next_occurrence_date > end_date
  end

  private
    def post_next_occurrence!(as_of)
      with_lock do
        if !active? || next_occurrence_date > as_of
          nil
        elsif ended?
          update!(active: false)
          nil
        else
          date = next_occurrence_date
          post_occurrence!(date)

          self.last_occurred_on = date
          self.occurrences_count += 1
          self.next_occurrence_date = occurrence_date(occurrences_count)
          self.active = false if ended?
          save!

          date
        end
      end
    end

    def post_occurrence!(date)
      transfer? ? post_transfer!(date) : post_transaction!(date)
    end

    def post_transaction!(date)
      account.entries.create!(
        name: name,
        date: date,
        currency: account.currency,
        amount: expense? ? amount : -amount,
        entryable: Transaction.new(category: category, recurring_transaction: self)
      )
    end

    def post_transfer!(date)
      transfer = Transfer::Creator.new(
        family: family,
        source_account_id: account_id,
        destination_account_id: destination_account_id,
        date: date,
        amount: amount
      ).create

      raise ActiveRecord::RecordInvalid, transfer unless transfer.persisted?

      transfer.inflow_transaction.update!(recurring_transaction: self)
      transfer.outflow_transaction.update!(recurring_transaction: self)
    end

    def schedule_changed?
      new_record? || will_save_change_to_start_date? || will_save_change_to_frequency?
    end

    # Recomputes the next date from start_date, skipping anything already posted so edits never re-post past dates
    def reschedule
      self.occurrences_count = 0
      if last_occurred_on
        self.occurrences_count += 1 while occurrence_date(occurrences_count) <= last_occurred_on
      end
      self.next_occurrence_date = occurrence_date(occurrences_count)
    end

    # Resuming a paused schedule picks up from today rather than backfilling everything missed while paused
    def skip_missed_occurrences
      self.occurrences_count += 1 while occurrence_date(occurrences_count) < Date.current
      self.next_occurrence_date = occurrence_date(occurrences_count)
    end

    def clear_fields_for_kind
      if transfer?
        self.category = nil
        self.name = nil
      else
        self.destination_account = nil
      end
    end

    def set_currency
      self.currency = account.currency if account
    end

    def associations_belong_to_family
      [ account, destination_account ].compact.each do |acc|
        errors.add(:base, "Account must belong to your family") unless acc.family_id == family_id
      end
      errors.add(:category, "must belong to your family") if category && category.family_id != family_id
    end

    def transfer_has_different_accounts
      return unless transfer? && account_id.present?
      errors.add(:destination_account, "must be different from the source account") if account_id == destination_account_id
    end

    def end_date_on_or_after_start_date
      return unless start_date && end_date
      errors.add(:end_date, "must be on or after the start date") if end_date < start_date
    end
end
