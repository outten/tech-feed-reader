require_relative '../database'

module Database
  # Rack middleware that scopes one pooled DB connection to each request.
  # Mounted as the OUTERMOST middleware in the production/dev Rack stack
  # (before RequestLogMiddleware, which writes pageviews to the DB), so
  # every middleware + the route runs on a single checked-out connection
  # and concurrent Puma threads don't share one socket.
  #
  # Not used by the test suite (specs drive TechFeedReader directly and
  # run single-threaded on the ambient connection).
  class ConnectionMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      Database.with_connection { @app.call(env) }
    end
  end
end
