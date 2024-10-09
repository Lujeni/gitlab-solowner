build:
	docker build -t gitlab-solowner:inactivity .

run: build
	docker run --rm gitlab-solowner:inactivity

local: build
	docker run --rm -it -v ${PWD}:/app gitlab-solowner:inactivity sh
