.PHONY: test module fixtures clean

TEST_IMAGE ?= ngx_http_geoip2_module:test
MODULE_IMAGE ?= ngx_http_geoip2_module:local

test:
	docker build --target test -t $(TEST_IMAGE) .
	tests/run.sh $(TEST_IMAGE)

module:
	docker build --target module -t $(MODULE_IMAGE) .

fixtures:
	docker run --rm -v "$(CURDIR)/tests/fixtures:/w" -w /w/generate golang:1.26-trixie \
		go run . ..

clean:
	docker rmi $(TEST_IMAGE) $(MODULE_IMAGE) 2>/dev/null || true
