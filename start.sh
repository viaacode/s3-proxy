bundle exec sidekiq -r $APP_DIR/app.rb -C $APP_DIR/config/sidekiq.yml &
bundle exec unicorn -c $APP_DIR/config/unicorn.rb

