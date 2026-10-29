class CreateRecurringTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :recurring_transactions, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :destination_account, foreign_key: { to_table: :accounts, on_delete: :cascade }, type: :uuid
      t.references :category, foreign_key: { on_delete: :nullify }, type: :uuid

      t.string :kind, null: false
      t.string :name
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.string :frequency, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.integer :occurrences_count, null: false, default: 0
      t.date :next_occurrence_date, null: false
      t.date :last_occurred_on
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :recurring_transactions, [ :active, :next_occurrence_date ]

    add_reference :transactions, :recurring_transaction, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
