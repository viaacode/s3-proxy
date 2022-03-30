# S3 Proxy voor VRT

1. VRT will do an S3 put request with a media file.
This is stored on our 100TB cache before saving to tape.
We store the ID given from VRT together with the file path in redis.

2. When later a S3 Get is send it's immediately returned from this cache using redis lookup (if file is present).
If file lookup fails it means the file has been moved to tape. We do a restore request to media haven
and return an xml with url + status busy.
VRT will keep requesting until file is present (protocol S3 if possible, if not something custom/similar to what they use internally).

3. Once the file is retrieved from tape we again store the path in the redis cache and also return it in previous request on 2.

Optionally a lookup table with postgres can be kept as backup which couples VRT id's to Mediahaven ids for the files (and spec for video or audio)

## Usefull links and reference material

* https://aws.amazon.com/premiumsupport/knowledge-center/restore-s3-object-glacier-storage-class/ : S3 protocol glacier
* https://integration.mediahaven.com/mediahaven-rest-api/#mediahaven-rest-api-manual-exporting  : media haven documentation for exporting from tape to storage
* https://gitlab.com/viaa/s3proxy2mam : current prototype. does not support uploads yet, can be used as reference
  * https://github.com/jamhall/s3rver : nodejs implementation of a s3 server, could be used as reference 
  * https://github.com/jubos/fake-s3 : ruby s3 server (but has licensing. so can be used as reference )

* Using minio is probably a more performant/easier option than trying to roll out a full custom s3 server: 
  * https://www.minio.io/
    * https://docs.minio.io/docs/python-client-quickstart-guide : minio S3 server and python SDK
    * https://github.com/minio/minio-ruby : minimal minio ruby sdk
    * https://docs.minio.io/docs/how-to-use-aws-sdk-for-ruby-with-minio-server.html : using aws sdk is also possible on custom minio server
    * pass-through vs direct https://devcenter.heroku.com/articles/s3. As noted it's preferable to do direct (being client connects to s3 directly)
    but to handle our tape storage client_restore request we'll most likely need a pass-through instead aka carrierwave and our temporary cache is
    then the place where the old proxy was having the ftp.
    https://devcenter.heroku.com/articles/direct-to-s3-image-uploads-in-rails

    * https://github.com/dwilkie/carrierwave_direct : also investigate this 
      * https://github.com/minio/cookbook/blob/master/docs/fog-aws-for-ruby-with-minio.md

    For performance it would be nice to re-use something like this gest so we proxy pass to minio or the s3 server of choice if we know the file is present somewhere:
    https://gist.github.com/fevangelou/beea28dcf76e2d47dd98
    and only forward to our sinatra app if its on tape and then allow polling+doing a restore request with sinatra and once the file is in place it can hit the s3 again.
    also for uploads preferably directly hit the s3...



## Installation
Just run bundle install then rake to run the automated tests.
Most test currently fail and need to be adjusted to wanted specs as we're TDD'ing.
Added some initial views, app skeleton, gemfile and test files to start working on initial version (work in progress...).


To test and run the minio S3 server just use the start_minio_server.sh helper script.
Then visit http://localhost:9999
enter key and pass specified in script file (TOPSECRET, ...) 
The minio_config and minio_data are mounted to this docker container and data can contain our video and audio data.
Example minio startup output:

```
➜  viaa-s3proxy git:(development) ✗ ./start_minio_server.sh
Using default tag: latest
latest: Pulling from minio/minio
Digest: sha256:14723eeb475edc7bd1ed1ffab87977a47112bec3ee18e2abeb579a2a19771705
Status: Image is up to date for minio/minio:latest
minio1
minio1

Endpoint:  http://172.17.0.2:9000  http://127.0.0.1:9000

Browser Access:
   http://172.17.0.2:9000  http://127.0.0.1:9000

Object API (Amazon S3 compatible):
   Go:         https://docs.minio.io/docs/golang-client-quickstart-guide
   Java:       https://docs.minio.io/docs/java-client-quickstart-guide
   Python:     https://docs.minio.io/docs/python-client-quickstart-guide
   JavaScript: https://docs.minio.io/docs/javascript-client-quickstart-guide
   .NET:       https://docs.minio.io/docs/dotnet-client-quickstart-guide
```


Our own sinatra app will expose some calls to interact with the minio instance (in this case, it can be any other s3 service later on).
On local machine run it with ./start_server.sh

```
➜  viaa-s3proxy git:(development) ✗ ./start_server.sh 
[7666] Puma starting in cluster mode...
[7666] * Version 3.12.0 (ruby 2.5.3-p105), codename: Llamas in Pajamas
[7666] * Min threads: 10, max threads: 10
[7666] * Environment: production
[7666] * Process workers: 2
[7666] * Phased restart available
[7666] * Listening on tcp://0.0.0.0:3000
[7666] Use Ctrl-C to stop
[7666] - Worker 0 (pid: 7681) booted, phase: 0
[7666] - Worker 1 (pid: 7682) booted, phase: 0

```




* First scenario:
  S3 put (object store can be minio, ceph : http://docs.ceph.com/docs/mimic/radosgw/s3/ or Caringo : https://www.caringo.com/connect/developers-s3)
  We proxy the call to the regular S3 store.
  https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPUT.html

  S3 get : we hit our app first and in case of existing (previously put) we can proxy to above S3 store.
  In case of 404 we now return a 404 also but this will be hook for second scenario
  https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html


* Second scenario S3 returns 404 but it's archived:
  Here we have a mediahaven or similar call with filename given and returning an object id or 404.
  In case of 404 we return same as in first scenario.
  In case of existing we return the 403 that triggers a restore request

  * S3 restore request (in case object stores don't support) we handle this also with our sinatra app which does:
    * https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPOSTrestore.html 
      request restore with media haven api and also make following head request return ongoing=true until file is restored.

    * handle head request : https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html 
      returns busy 200 ok head HEAD /<bucket>/<filename> s3:GetObjectMetadata [^4] 
        x-amz-restore: ongoing-request="true" 
 
 ### Openshift deployment note
 
 The app uses the `X-Forwarded-Host` header to determine the s3 domain. This header is set by the meemoo nginx proxy.
 In its default configuration, the OKD router adds the hostname of the router to this header which confuses the app.
 Therefore the okd route associated with this app must have the following annotation set:
 ```yaml
   annotations:
    haproxy.router.openshift.io/set-forwarded-headers: if-none
  ```
