CURRENT_USER=$(shell id -u)
CURRENT_GROUP=$(shell id -g)

.PHONY: test
test:
	cd "$(CURDIR)/pISO" && cargo test

.PHONY: test-ci
test-ci:
	podman run --rm \
		-e CARGO_HOME='$(CARGO_HOME)'\
		--user $(CURRENT_USER):$(CURRENT_GROUP) \
		-v "$(PWD)":$(PWD) -w $(PWD)/pISO rust:1 cargo test

.PHONY: sdimage
sdimage: update-config
ifeq ("$(shell ./scripts/should-rebuild)","rebuild")
	sudo podman run --net=host -v $(CURDIR):/pISO -w /pISO/buildroot \
			--user $(CURRENT_USER):$(CURRENT_GROUP) \
			--rm  adamschwalm/piso:latest /bin/bash -c "make clean && make"
else
	sudo podman run --net=host -v $(CURDIR):/pISO -w /pISO/buildroot \
			--user $(CURRENT_USER):$(CURRENT_GROUP) \
			--rm  adamschwalm/piso:latest /bin/bash -c "make piso-reconfigure && make"
endif
	git submodule > buildroot/output/.cache-version

.PHONY: sdimage-ci
sdimage-ci: update-config
	chmod +x buildroot/board/piso/post-build.sh
	chmod +x buildroot/board/piso/post-image.sh
ifeq ("$(shell ./scripts/should-rebuild)","rebuild")
	podman run -v $(CURDIR):/pISO -w /pISO/buildroot \
			--user $(CURRENT_USER):$(CURRENT_GROUP) \
			--rm  adamschwalm/piso:latest /bin/bash -c "make clean && make"
else
	podman run -v $(CURDIR):/pISO -w /pISO/buildroot \
			--user $(CURRENT_USER):$(CURRENT_GROUP) \
			--rm  adamschwalm/piso:latest /bin/bash -c "make piso-reconfigure && make"
endif
	git submodule > buildroot/output/.cache-version
	zip -j sdcard.img.zip buildroot/output/images/sdcard.img
	zip -j update.zip buildroot/output/images/zImage \
	                  buildroot/output/images/rootfs.squashfs \
	                  buildroot/output/images/initramfs.cpio.lzo
.PHONY: update-config
update-config:
	cd "$(CURDIR)/buildroot" && cp "configs/piso_defconfig" ".config"

BENCHMARK_FLAGS=--direct=1 --ioengine=libaio \
		--bs=64k --numjobs=1 --size=1G --runtime=600 --group_reporting

.PHONY: benchmark
.ONESHELL:
benchmark:
ifndef TARGET
	$(error benchmark TARGET is undefined)
endif
	@cd $(TARGET)
	@echo "--------------SEQWRITE------------------------------"
	@sudo fio --name=seqwrite --rw=write $(BENCHMARK_FLAGS)
	@echo "--------------RANDWRITE------------------------------"
	@sudo fio --name=randwrite --rw=randwrite $(BENCHMARK_FLAGS)
	@echo "--------------SEQREAD------------------------------"
	@sudo fio --name=seqread --rw=read $(BENCHMARK_FLAGS)
	@echo "--------------RANDREAD------------------------------"
	@sudo fio --name=randread --rw=randread $(BENCHMARK_FLAGS)
