.PHONY: test test-alpine coverage module fixtures clean

TEST_IMAGE ?= ngx_http_geoip2_module:test
TEST_ALPINE_IMAGE ?= ngx_http_geoip2_module:test-alpine
COVERAGE_IMAGE ?= ngx_http_geoip2_module:coverage
MODULE_IMAGE ?= ngx_http_geoip2_module:local

# The nginx branch to build for: mainline or stable.
NGINX_BRANCH ?= mainline
NGINX_VERSION ?= $(shell scripts/nginx-version.sh $(NGINX_BRANCH))
BUILD = docker build --build-arg NGINX_VERSION=$(NGINX_VERSION)

test:
	$(BUILD) --target test -t $(TEST_IMAGE) .
	tests/run.sh $(TEST_IMAGE)

test-alpine:
	$(BUILD) --target test-alpine -t $(TEST_ALPINE_IMAGE) .
	tests/run.sh $(TEST_ALPINE_IMAGE)

coverage:
	$(BUILD) --target coverage -t $(COVERAGE_IMAGE) .
	tests/coverage.sh $(COVERAGE_IMAGE) build

module:
	$(BUILD) --target module -t $(MODULE_IMAGE) .

fixtures:
	docker run --rm -v "$(CURDIR)/tests/fixtures:/w" -w /w/generate golang:1.26-trixie \
		go run . ..

clean:
	docker rmi $(TEST_IMAGE) $(TEST_ALPINE_IMAGE) $(COVERAGE_IMAGE) $(MODULE_IMAGE) 2>/dev/null || true
