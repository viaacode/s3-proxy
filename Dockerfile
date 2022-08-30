FROM ruby:2.6.4-alpine3.10

WORKDIR /usr/src/app

ENV BUNDLER_VERSION='2.1.4'
COPY Gemfile Gemfile.lock /usr/src/app/
RUN chmod +w Gemfile.lock && gem update --system && gem install bundler -v 2.1.4

# linux headers for unicorn gems build
RUN apk update && \
  apk add --virtual build-dependencies \
                    yaml yaml-dev \
                    gcc g++ make \
                    linux-headers \ 
  && cd /usr/src/app && bundle update --bundler && bundle install \
  && apk del build-dependencies \
  && rm -rf /var/cache/apk/*

EXPOSE 3000

# Create appuser and group for unicorn to add tmp files
# Make compatible with openshift
RUN adduser -G root -S appuser

ENV APP_DIR /usr/src/app
ENV PORT 3000
ENV PUMA_THREADS 10
ENV WORKERS 4
ENV S3_SERVER http://minio:9999
ENV REDIS_URL redis://127.0.0.1:6379/2
ENV REDIS_EXPIRE 20
ENV MEDIAHAVEN_API http://example.org
ENV MEDIAHAVEN_USER apiUser
ENV MEDIAHAVEN_PASS apiPass
ENV TENANT_API http://example.org
ENV TENANT_USER tenantUser
ENV TENANT_PASS somepass
# This is the mediahave S3 location
ENV EXPORT_LOCATION_ID 1188
# Poll every minute by default
ENV STATUS_POLL_INTERVAL=60
# Stop polling after 2 days
ENV STATUS_MAX_POLL_COUNT=2880

COPY . /usr/src/app/

RUN mkdir -p /usr/src/app/log /usr/src/app/tmp \
  && chmod -R g+w /usr/src/app/tmp /usr/src/app/log /usr/src/app/test/data

USER appuser

#CMD bundle exec unicorn -c /usr/src/app/config/unicorn.rb
CMD /usr/src/app/start.sh
