require "test_helper"

class RecurringTransactionsJobTest < ActiveJob::TestCase
  test "posts due recurring transactions and skips paused ones" do
    due = recurring_transactions(:subscription)
    due.update_columns(next_occurrence_date: Date.current, start_date: Date.current)

    paused = recurring_transactions(:loan_payment)
    paused.update_columns(next_occurrence_date: Date.current, start_date: Date.current, active: false)

    assert_difference "Entry.count", 1 do
      RecurringTransactionsJob.perform_now
    end

    assert_equal Date.current.advance(months: 1), due.reload.next_occurrence_date
    assert_equal Date.current, paused.reload.next_occurrence_date
  end
end
