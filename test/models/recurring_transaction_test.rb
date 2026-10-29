require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @loan = accounts(:loan)
  end

  test "posts a due expense once and advances to the next month" do
    recurring = create_expense(start_date: Date.current)

    assert_difference "@checking.entries.count", 1 do
      recurring.post_due!
    end

    entry = @checking.entries.order(:created_at).last
    assert_equal 20, entry.amount
    assert_equal Date.current, entry.date
    assert_equal recurring, entry.entryable.recurring_transaction
    assert_equal Date.current.advance(months: 1), recurring.reload.next_occurrence_date

    assert_no_difference "@checking.entries.count" do
      recurring.post_due!
    end
  end

  test "posts income as an inflow" do
    recurring = create_expense(kind: "income", name: "Salary", start_date: Date.current)
    recurring.post_due!

    assert_equal(-20, @checking.entries.order(:created_at).last.amount)
  end

  test "catches up missed occurrences" do
    recurring = create_expense(start_date: 2.months.ago.to_date)

    assert_difference "@checking.entries.count", 3 do
      recurring.post_due!
    end
  end

  test "monthly schedules anchored on the 31st clamp to month end without drifting" do
    recurring = create_expense(start_date: Date.new(2025, 1, 31))

    assert_equal Date.new(2025, 2, 28), recurring.occurrence_date(1)
    assert_equal Date.new(2025, 3, 31), recurring.occurrence_date(2)
  end

  test "posts a transfer to a loan as a loan payment" do
    recurring = @family.recurring_transactions.create!(
      kind: "transfer", account: @checking, destination_account: @loan,
      amount: 500, frequency: "monthly", start_date: Date.current
    )

    assert_difference "Transfer.count", 1 do
      recurring.post_due!
    end

    transfer = Transfer.order(:created_at).last
    assert transfer.loan_payment?
    assert_equal recurring, transfer.outflow_transaction.recurring_transaction
    assert_equal "Payment to #{@loan.name}", recurring.display_name
  end

  test "deactivates once the end date has passed" do
    recurring = create_expense(start_date: 1.month.ago.to_date, end_date: Date.current - 1.day)

    assert_difference "@checking.entries.count", 1 do
      recurring.post_due!
    end

    assert_not recurring.reload.active?
  end

  test "changing the schedule does not re-post past occurrences" do
    recurring = create_expense(start_date: 1.month.ago.to_date)
    recurring.post_due!

    recurring.update!(frequency: "weekly")

    assert recurring.next_occurrence_date > recurring.last_occurred_on
    assert_no_difference "@checking.entries.count" do
      recurring.post_due!(as_of: recurring.last_occurred_on)
    end
  end

  test "resuming a paused schedule skips occurrences missed while paused" do
    recurring = create_expense(start_date: 1.month.from_now.to_date)
    recurring.update!(active: false)
    recurring.update_columns(next_occurrence_date: 2.months.ago.to_date, start_date: 2.months.ago.to_date, occurrences_count: 0)

    recurring.update!(active: true)

    assert recurring.next_occurrence_date >= Date.current
  end

  test "requires a different destination account for transfers" do
    recurring = @family.recurring_transactions.build(
      kind: "transfer", account: @checking, destination_account: @checking,
      amount: 100, frequency: "monthly", start_date: Date.current
    )

    assert_not recurring.valid?
  end

  private
    def create_expense(**attrs)
      @family.recurring_transactions.create!(
        { kind: "expense", name: "Claude subscription", account: @checking, amount: 20, frequency: "monthly" }.merge(attrs)
      )
    end
end
