verification: clean
	mkdir -p build
	./spin_651 -a -m1000000 sctp.pml
	mv pan* build/
	gcc -DNXT -DNOREDUCE build/pan.c -o verif

clean:
	rm -rf ./build/*
	rm -f pan*
	rm -f verif
	rm -f *.tmp
