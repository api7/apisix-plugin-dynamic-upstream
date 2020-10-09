### help:             Show Makefile rules
.PHONY: help
help: default
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### test:             Run the test case
test:
	APISIX_HOME=../apisix prove -I../apisix/  t/plugin/*.t
  
