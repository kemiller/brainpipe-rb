module Brainpipe
  module Rails
    class Execution < ActiveRecord::Base
      self.table_name = "brainpipe_executions"

      enum :status, {
        pending: "pending",
        running: "running",
        completed: "completed",
        failed: "failed"
      }

      validates :pipe_name, presence: true
    end
  end
end
