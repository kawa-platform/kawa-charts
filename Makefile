.PHONY: help release

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

release: ## Interactive kawa release: components first, waits for each build, then the kawa chart
	@./scripts/release.sh
