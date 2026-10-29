class RecurringTransactionsJob < ApplicationJob
  queue_as :scheduled

  def perform
    RecurringTransaction.due.find_each do |recurring_transaction|
      recurring_transaction.post_due!
    rescue => e
      Rails.logger.error("Failed to post recurring transaction #{recurring_transaction.id}: #{e.message}")
      Sentry.capture_exception(e)
    end
  end
end
