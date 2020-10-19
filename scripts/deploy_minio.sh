oc login
oc project s3proxy
#oc import-image s3proxy --from=registry.gitlab.com/viaa/viaa-s3proxy/viaas3proxy:latest --confirm
oc import-image s3proxy-minio --from=registry.gitlab.com/viaa/viaa-s3proxy/minio:latest --confirm

