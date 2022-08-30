# frozen_string_literal: true

app_dir = ENV.fetch('APP_DIR', '/usr/src/app')
worker_processes ENV.fetch('WORKERS', 4).to_i
working_directory app_dir
pid "#{app_dir}/tmp/unicorn.pid"

listen ENV.fetch('PORT', 5000), tcp_nopush: true
timeout 30
