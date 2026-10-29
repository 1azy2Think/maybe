class RecurringTransactionsController < ApplicationController
  include StreamExtensions

  before_action :set_recurring_transaction, only: %i[edit update destroy]
  before_action :set_form_options, only: %i[new create edit update]

  def index
    @recurring_transactions = Current.family.recurring_transactions
                                     .includes(:account, :destination_account, :category)
                                     .by_next_occurrence
    render layout: "settings"
  end

  def new
    @recurring_transaction = Current.family.recurring_transactions.build(
      kind: params[:kind].presence_in(RecurringTransaction.kinds.keys) || "expense",
      frequency: "monthly",
      start_date: Date.current
    )
  end

  def create
    @recurring_transaction = Current.family.recurring_transactions.build(recurring_transaction_params)

    if @recurring_transaction.save
      posted_dates = @recurring_transaction.post_due!
      notice = posted_dates.any? ? "Recurring #{@recurring_transaction.kind} created and #{posted_dates.size} posted" : "Recurring #{@recurring_transaction.kind} created"

      respond_to do |format|
        format.html { redirect_to recurring_transactions_path, notice: notice }
        format.turbo_stream { stream_redirect_to recurring_transactions_path, notice: notice }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @recurring_transaction.update(recurring_transaction_params)
      @recurring_transaction.post_due!

      respond_to do |format|
        format.html { redirect_back_or_to recurring_transactions_path, notice: "Recurring #{@recurring_transaction.kind} updated" }
        format.turbo_stream { stream_redirect_back_or_to recurring_transactions_path, notice: "Recurring #{@recurring_transaction.kind} updated" }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_transaction.destroy!
    redirect_to recurring_transactions_path, notice: "Recurring #{@recurring_transaction.kind} deleted"
  end

  private
    def set_recurring_transaction
      @recurring_transaction = Current.family.recurring_transactions.find(params[:id])
    end

    def set_form_options
      @accounts = Current.family.accounts.manual.active.alphabetically
      @income_categories = Current.family.categories.incomes.alphabetically
      @expense_categories = Current.family.categories.expenses.alphabetically
    end

    # Associations are looked up through the current family rather than mass-assigned by id
    def recurring_transaction_params
      permitted = params.require(:recurring_transaction).permit(
        :kind, :name, :amount, :frequency, :start_date, :end_date, :active
      )

      raw = params[:recurring_transaction]
      permitted[:account] = find_family_record(Current.family.accounts, raw[:account_id]) if raw.key?(:account_id)
      permitted[:destination_account] = find_family_record(Current.family.accounts, raw[:destination_account_id]) if raw.key?(:destination_account_id)
      permitted[:category] = find_family_record(Current.family.categories, raw[:category_id]) if raw.key?(:category_id)
      permitted
    end

    def find_family_record(scope, id)
      id.present? ? scope.find(id) : nil
    end
end
