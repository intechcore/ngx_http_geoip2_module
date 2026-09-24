.PHONY: test test-alpine integration asan analyze coverage module fixtures clean

TEST_IMAGE ?= ngx_http_geoip2_module:test
TEST_ALPINE_IMAGE ?= ngx_http_geoip2_module:test-alpine
COVERAGE_IMAGE ?= ngx_http_geoip2_module:coverage
ASAN_IMAGE ?= ngx_http_geoip2_module:asan
MODULE_IMAGE ?= ngx_http_geoip2_module:local

# The nginx branch to build for: mainline or stable. The Dockerfile pins its
# base images, scripts/nginx-image.sh reads them.
NGINX_BRANCH ?= mainline
NGINX_IMAGE ?= $(shell scripts/nginx-image.sh $(NGINX_BRANCH) debian)
NGINX_ALPINE_IMAGE ?= $(shell scripts/nginx-image.sh $(NGINX_BRANCH) alpine)
BUILD = docker build --build-arg NGINX_IMAGE=$(NGINX_IMAGE) --build-arg NGINX_ALPINE_IMAGE=$(NGINX_ALPINE_IMAGE)

test:
	$(BUILD) --target test -t $(TEST_IMAGE) .
	tests/run.sh $(TEST_IMAGE)

test-alpine:
	$(BUILD) --target test-alpine -t $(TEST_ALPINE_IMAGE) .
	tests/run.sh $(TEST_ALPINE_IMAGE)

integration:
	$(BUILD) --target test -t $(TEST_IMAGE) .
	tests/integration/run.sh $(TEST_IMAGE)

asan:
	$(BUILD) --target asan -t $(ASAN_IMAGE) .
	tests/run.sh $(ASAN_IMAGE)

analyze:
	$(BUILD) --target analyze .

coverage:
	$(BUILD) --target coverage -t $(COVERAGE_IMAGE) .
	tests/coverage.sh $(COVERAGE_IMAGE) build

module:
	$(BUILD) --target module -t $(MODULE_IMAGE) .

fixtures:
	docker run --rm -v "$(CURDIR)/tests/fixtures:/w" -w /w/generate golang:1.26-trixie \
		go run . ..

clean:
	docker rmi $(TEST_IMAGE) $(TEST_ALPINE_IMAGE) $(ASAN_IMAGE) $(COVERAGE_IMAGE) $(MODULE_IMAGE) 2>/dev/null || true
