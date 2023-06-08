
DOCKER_BUILDX_OUTPUT ?= type=registry
DOCKER_BUILDX_PLATFORM ?= linux/amd64
CTR_REGISTRY = cybwan

.PHONY: docker-build-account-service
docker-build-account-service:
	docker buildx build --builder fsm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) \
	-t $(CTR_REGISTRY)/spring-consul-demo:acount-service \
	-f dockerfiles/Dockerfile.account-service .

.PHONY: docker-build-customer-service
docker-build-customer-service:
	docker buildx build --builder fsm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) \
	-t $(CTR_REGISTRY)/spring-consul-demo:customer-service \
	-f dockerfiles/Dockerfile.customer-service .

.PHONY: docker-build-gateway-service
docker-build-gateway-service:
	docker buildx build --builder fsm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) \
	-t $(CTR_REGISTRY)/spring-consul-demo:gateway-service \
	-f dockerfiles/Dockerfile.gateway-service .

.PHONY: docker-build-order-service
docker-build-order-service:
	docker buildx build --builder fsm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) \
	-t $(CTR_REGISTRY)/spring-consul-demo:order-service \
	-f dockerfiles/Dockerfile.order-service .

.PHONY: docker-build-product-service
docker-build-product-service:
	docker buildx build --builder fsm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) \
	-t $(CTR_REGISTRY)/spring-consul-demo:product-service \
	-f dockerfiles/Dockerfile.product-service .

DEMO_TARGETS = account-service customer-service gateway-service order-service product-service
DOCKER_DEMO_TARGETS = $(addprefix docker-build-, $(DEMO_TARGETS))
.PHONY: $(DOCKER_DEMO_TARGETS)
$(DOCKER_DEMO_TARGETS): NAME=$(@:docker-build-%=%)

.PHONY: docker-build-demo
docker-build-demo: $(DOCKER_DEMO_TARGETS)
