VERSION = ${shell (git describe --tags || echo latest)}

.ONESHELL:
SHELL = /bin/bash

.PHONY: all

NAMESPACE = s3-components
OC_PROJECT = ${NAMESPACE}

APP_NAME = s3-proxy
IMAGE_NAME = ${NAMESPACE}/${APP_NAME}
REGISTRY = docker-registry-default.apps.do-prd-okp-m0.do.viaa.be
login:
	login_oc.sh https://do-prd-okp-m0.do.viaa.be:8443
	oc project "${OC_PROJECT}"
build:
	cp ./.env.example ./.env
	docker build -t "${REGISTRY}/${IMAGE_NAME}:${VERSION}" .
test:
	docker network create test
	docker container run -d --net test -p 6379:6379 -v "redis:/data" --name "redis" "redis:4.0-alpine" "redis-server"
	docker container run  --net test --name "${APP_NAME}_test"  --env-file .env \
					--entrypoint rake "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
lint:
	docker container run --name "${APP_NAME}_lint" \
					--entrypoint rubocop "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
push: 	login
	docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}

tag-int:
	oc tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:int
deploy-int:
test-int:

tag-qas:
	oc tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:qas
deploy-qas:
	bash ./openshift/wait4rollout.sh qas ${APP_NAME}
test-qas:

tag-prd:
	oc tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:prd
deploy-prd:

approved:
	echo "Approved"

post-clean:
	docker container rm -f "redis"
	docker container rm "${APP_NAME}_test"
	docker container rm "${APP_NAME}_lint"
	docker network remove test
