ERLC = erlc
SRC = $(wildcard src/*.erl)
BEAMS = $(patsubst src/%.erl,ebin/%.beam,$(SRC))

.PHONY: all clean

all: ntrip_bridge

ebin:
	mkdir -p ebin

ebin/%.beam: src/%.erl | ebin
	$(ERLC) -o ebin $<

ebin/ntrip_bridge.app: src/ntrip_bridge.app.src | ebin
	cp $< $@

ntrip_bridge: $(BEAMS) ebin/ntrip_bridge.app
	escript build_escript.escript
	chmod +x ntrip_bridge

clean:
	rm -rf ebin ntrip_bridge erl_crash.dump
