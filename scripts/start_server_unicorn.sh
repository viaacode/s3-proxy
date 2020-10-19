mkdir -p tmp
# redis expiry best set to approximately the duration it takes to move file to tape archive after initial upload
# REDIS_URL=redis://127.0.0.1:6379/2 REDIS_EXPIRE=200 \
REDIS_URL=redis://127.0.0.1:6379/0 REDIS_EXPIRE=20 \
S3_SERVER=http://localhost:9999/minio \
MEDIAHAVEN_API=$MEDIAHAVEN_API \
MEDIAHAVEN_USER=$MEDIAHAVEN_USER \
MEDIAHAVEN_PASS=$MEDIAHAVEN_PASS \
PORT=3000 PUMA_THREADS=2 WORKERS=4 \
RAILS_ENV=production \
APP_DIR=/Users/wschrep/FreelanceWork/VIAA/viaa-s3proxy/ \
bundle exec unicorn -c config/unicorn.rb

