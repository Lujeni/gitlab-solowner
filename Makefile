build:
	docker build -t gitlab-solowner .

run: build
	docker run --rm gitlab-solowner

local: build
	docker run --rm -it -v ${PWD}:/app gitlab-solowner sh
