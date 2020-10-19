SERVER=https://do-prd-okp-m0.do.viaa.be:8443

oc login $SERVER
oc project s3proxy
oc import-image s3proxy --from=registry.gitlab.com/viaa/viaa-s3proxy/viaas3proxy:latest --confirm

