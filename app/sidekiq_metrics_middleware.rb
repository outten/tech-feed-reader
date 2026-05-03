require_relative 'metrics'

# Sidekiq server middleware — wraps every job execution, increments
# `tfr_sidekiq_jobs_total{worker, status}` once it terminates, and
# observes the duration into the job-duration histogram. The `status`
# label is `success` when the job's perform returns normally and
# `failed` when it raises (we re-raise so Sidekiq's normal retry path
# still runs).
class SidekiqMetricsMiddleware
  def call(worker, _job, _queue)
    start  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = 'success'
    yield
  rescue StandardError
    status = 'failed'
    raise
  ensure
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    name     = worker.class.name
    Metrics::SIDEKIQ_JOBS.increment(labels: { worker: name, status: status })
    Metrics::SIDEKIQ_JOB_DURATION.observe(duration, labels: { worker: name })
  end
end
