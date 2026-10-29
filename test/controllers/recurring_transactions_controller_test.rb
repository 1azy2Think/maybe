require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @recurring = recurring_transactions(:subscription)
  end

  test "should get index" do
    get recurring_transactions_url
    assert_response :success
  end

  test "should get new for each kind" do
    %w[expense income transfer].each do |kind|
      get new_recurring_transaction_url(kind: kind)
      assert_response :success
    end
  end

  test "should get edit" do
    get edit_recurring_transaction_url(@recurring)
    assert_response :success
  end

  test "creates an expense and posts the first occurrence when due" do
    assert_difference [ "RecurringTransaction.count", "Entry.count" ], 1 do
      post recurring_transactions_url, params: {
        recurring_transaction: {
          kind: "expense", name: "Claude", account_id: accounts(:depository).id,
          amount: 20, frequency: "monthly", start_date: Date.current
        }
      }
    end

    assert_redirected_to recurring_transactions_url
  end

  test "creates a transfer" do
    assert_difference [ "RecurringTransaction.count", "Transfer.count" ], 1 do
      post recurring_transactions_url, params: {
        recurring_transaction: {
          kind: "transfer", account_id: accounts(:depository).id, destination_account_id: accounts(:loan).id,
          amount: 500, frequency: "biweekly", start_date: Date.current
        }
      }
    end
  end

  test "pauses a recurring transaction" do
    patch recurring_transaction_url(@recurring), params: { recurring_transaction: { active: "0" } }

    assert_not @recurring.reload.active?
  end

  test "destroys a recurring transaction" do
    assert_difference "RecurringTransaction.count", -1 do
      delete recurring_transaction_url(@recurring)
    end

    assert_redirected_to recurring_transactions_url
  end
end
