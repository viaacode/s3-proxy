# redis expiry best set to approximately the duration it takes to move file to tape archive after initial upload
REDIS_URL=redis://127.0.0.1:6379/2 REDIS_EXPIRE=200 \
S3_SERVER=http://localhost:9999 \
MEDIAHAVEN_API=$MEDIAHAVEN_API \
MEDIAHAVEN_USER=$MEDIAHAVEN_USER \
MEDIAHAVEN_PASS=$MEDIAHAVEN_PASSWORD \
PORT=3000 PUMA_THREADS=10 WORKERS=2 \
bundle exec puma config.ru -C config/puma.rb -e production


