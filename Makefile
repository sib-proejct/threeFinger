.PHONY: app dmg test clean

app:
	./scripts/build-app.sh

dmg:
	./scripts/build-dmg.sh

test:
	cargo test

clean:
	rm -rf dist target
