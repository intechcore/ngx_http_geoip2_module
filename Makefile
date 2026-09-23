.PHONY: test coverage module fixtures clean

TEST_IMAGE ?= ngx_http_geoip2_module:test
COVERAGE_IMAGE ?= ngx_http_geoip2_module:coverage
MODULE_IMAGE ?= ngx_http_geoip2_module:local

test:
	docker build --target test -t $(TEST_IMAGE) .
	tests/run.sh $(TEST_IMAGE)

coverage:
	docker build --target coverage -t $(COVERAGE_IMAGE) .
	tests/coverage.sh $(COVERAGE_IMAGE) build

module:
	docker build --target module -t $(MODULE_IMAGE) .

fixtures:
	docker run --rm -v "$(CURDIR)/tests/fixtures:/w" -w /w/generate golang:1.26-trixie \
		go run . ..

clean:
	docker rmi $(TEST_IMAGE) $(COVERAGE_IMAGE) $(MODULE_IMAGE) 2>/dev/null || true
