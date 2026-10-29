# Entry point for external schedulers (e.g. Vercel Cron) on hosts where the
# Sidekiq process isn't always running, so sidekiq-cron ticks get missed.
class CronController < ApplicationController
  skip_authentication

  before_action :verify_cron_secret

  def daily
    ImportMarketDataJob.perform_later(mode: "full", clear_cache: false)
    SyncCleanerJob.perform_later
    SecurityHealthCheckJob.perform_later

    head :ok
  end

  private
    def verify_cron_secret
      secret = ENV["CRON_SECRET"]
      provided = request.headers["Authorization"].to_s

      unless secret.present? && ActiveSupport::SecurityUtils.secure_compare(provided, "Bearer #{secret}")
        head :unauthorized
      end
    end
end
