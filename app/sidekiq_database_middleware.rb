require_relative 'database'

# Sidekiq server middleware: scope one pooled DB connection to each job,
# mirroring Database::ConnectionMiddleware for web requests. Without it,
# every worker thread would fall back to the ambient connection and
# serialize on its Monitor. Added outermost in the server chain so the
# whole job (and any inner middleware) runs on the checked-out connection.
class SidekiqDatabaseMiddleware
  def call(_worker, _job, _queue)
    Database.with_connection { yield }
  end
end
