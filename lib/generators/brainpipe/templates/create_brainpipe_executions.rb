class CreateBrainpipeExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :brainpipe_executions, id: :uuid do |t|
      t.string :pipe_name, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :input, default: {}
      t.jsonb :result, default: {}
      t.jsonb :error, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index :status
      t.index :pipe_name
      t.index :created_at
    end
  end
end
