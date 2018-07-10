#!/bin/sh

test_description='multi-pack-indexes'
. ./test-lib.sh

objdir=.git/objects

midx_read_expect () {
	NUM_PACKS=$1
	NUM_OBJECTS=$2
	NUM_CHUNKS=$3
	OBJECT_DIR=$4
	EXTRA_CHUNKS="$5"
	cat >expect <<-EOF
	header: 4d494458 1 $NUM_CHUNKS $NUM_PACKS
	chunks: pack_names oid_fanout oid_lookup object_offsets$EXTRA_CHUNKS
	num_objects: $NUM_OBJECTS
	packs:
	EOF
	if [ $NUM_PACKS -ge 1 ]
	then
		ls $OBJECT_DIR/pack/ | grep idx | sort >> expect
	fi
	printf "object_dir: $OBJECT_DIR\n" >>expect &&
	test-tool read-midx $OBJECT_DIR >actual &&
	test_cmp expect actual
}

test_expect_success 'write midx with no packs' '
	test_when_finished rm -f pack/multi-pack-index &&
	git multi-pack-index --object-dir=. write &&
	midx_read_expect 0 0 4 .
'

test_expect_success 'create objects' '
	for i in $(test_seq 1 5)
	do
		iii=$(printf '%03i' $i)
		test-tool genrandom "bar" 200 >wide_delta_$iii &&
		test-tool genrandom "baz $iii" 50 >>wide_delta_$iii &&
		test-tool genrandom "foo"$i 100 >deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 1) 100 >>deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 2) 100 >>deep_delta_$iii &&
		echo $iii >file_$iii &&
		test-tool genrandom "$iii" 8192 >>file_$iii &&
		git update-index --add file_$iii deep_delta_$iii wide_delta_$iii &&
		i=$(expr $i + 1) || return 1
	done &&
	{ echo 101 && test-tool genrandom 100 8192; } >file_101 &&
	git update-index --add file_101 &&
	tree=$(git write-tree) &&
	commit=$(git commit-tree $tree </dev/null) && {
	echo $tree &&
	git ls-tree $tree | sed -e "s/.* \\([0-9a-f]*\\)	.*/\\1/"
	} >obj-list &&
	git update-ref HEAD $commit
'

test_expect_success 'write midx with one v1 pack' '
	pack=$(git pack-objects --index-version=1 pack/test <obj-list) &&
	test_when_finished rm pack/test-$pack.pack pack/test-$pack.idx pack/multi-pack-index &&
	git multi-pack-index --object-dir=. write &&
	midx_read_expect 1 17 4 .
'

midx_git_two_modes() {
	git -c core.multiPackIndex=false $1 >expect &&
	git -c core.multiPackIndex=true $1 >actual &&
	test_cmp expect actual
}

compare_results_with_midx() {
	MSG=$1
	test_expect_success "check normal git operations: $MSG" '
		midx_git_two_modes "rev-list --objects --all" &&
		midx_git_two_modes "log --raw"
	'
}

test_expect_success 'write midx with one v2 pack' '
	git pack-objects --index-version=2,0x40 $objdir/pack/test <obj-list &&
	git multi-pack-index --object-dir=$objdir write &&
	midx_read_expect 1 17 4 $objdir
'

midx_git_two_modes() {
	git -c core.multiPackIndex=false $1 >expect &&
	git -c core.multiPackIndex=true $1 >actual &&
	test_cmp expect actual
}

compare_results_with_midx() {
	MSG=$1
	test_expect_success "check normal git operations: $MSG" '
		midx_git_two_modes "rev-list --objects --all" &&
		midx_git_two_modes "log --raw" &&
		midx_git_two_modes "log --oneline"
	'
}

compare_results_with_midx "one v2 pack"

test_expect_success 'Add more objects' '
	for i in $(test_seq 6 10)
	do
		iii=$(printf '%03i' $i)
		test-tool genrandom "bar" 200 >wide_delta_$iii &&
		test-tool genrandom "baz $iii" 50 >>wide_delta_$iii &&
		test-tool genrandom "foo"$i 100 >deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 1) 100 >>deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 2) 100 >>deep_delta_$iii &&
		echo $iii >file_$iii &&
		test-tool genrandom "$iii" 8192 >>file_$iii &&
		git update-index --add file_$iii deep_delta_$iii wide_delta_$iii &&
		i=$(expr $i + 1) || return 1
	done &&
	{ echo 101 && test-tool genrandom 100 8192; } >file_101 &&
	git update-index --add file_101 &&
	tree=$(git write-tree) &&
	commit=$(git commit-tree $tree -p HEAD</dev/null) && {
	echo $tree &&
	git ls-tree $tree | sed -e "s/.* \\([0-9a-f]*\\)	.*/\\1/"
	} >obj-list2 &&
	git update-ref HEAD $commit
'

test_expect_success 'write midx with two packs' '
	git pack-objects --index-version=1 $objdir/pack/test-2 <obj-list2 &&
	git multi-pack-index --object-dir=$objdir write &&
	midx_read_expect 2 33 4 $objdir
'

compare_results_with_midx "two packs"

test_expect_success 'Add more packs' '
	for j in $(test_seq 1 10)
	do
		iii=$(printf '%03i' $i)
		test-tool genrandom "bar" 200 >wide_delta_$iii &&
		test-tool genrandom "baz $iii" 50 >>wide_delta_$iii &&
		test-tool genrandom "foo"$i 100 >deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 1) 100 >>deep_delta_$iii &&
		test-tool genrandom "foo"$(expr $i + 2) 100 >>deep_delta_$iii &&
		echo $iii >file_$iii &&
		test-tool genrandom "$iii" 8192 >>file_$iii &&
		git update-index --add file_$iii deep_delta_$iii wide_delta_$iii &&
		{ echo 101 && test-tool genrandom 100 8192; } >file_101 &&
		git update-index --add file_101 &&
		tree=$(git write-tree) &&
		commit=$(git commit-tree $tree -p HEAD</dev/null) && {
		echo $tree &&
		git ls-tree $tree | sed -e "s/.* \\([0-9a-f]*\\)	.*/\\1/"
		} >obj-list &&
		git update-ref HEAD $commit &&
		git pack-objects --index-version=2 $objdir/pack/test-pack <obj-list &&
		i=$(expr $i + 1) || return 1 &&
		j=$(expr $j + 1) || return 1
	done
'

compare_results_with_midx "mixed mode (two packs + extra)"

test_expect_success 'write midx with twelve packs' '
	git multi-pack-index --object-dir=$objdir write &&
	midx_read_expect 12 73 4 $objdir
'

compare_results_with_midx "twelve packs"

# usage: corrupt_data <file> <pos> [<data>]
corrupt_data() {
	file=$1
	pos=$2
	data="${3:-\0}"
	printf "$data" | dd of="$file" bs=1 seek="$pos" conv=notrunc
}

# Force 64-bit offsets by manipulating the idx file.
# This makes the IDX file _incorrect_ so be careful to clean up after!
test_expect_success 'force some 64-bit offsets with pack-objects' '
	mkdir objects64 &&
	mkdir objects64/pack &&
	pack64=$(git pack-objects --index-version=2,0x40 objects64/pack/test-64 <obj-list) &&
	idx64=objects64/pack/test-64-$pack64.idx &&
	chmod u+w $idx64 &&
	corrupt_data $idx64 2899 "\02" &&
	midx64=$(git multi-pack-index write --object-dir=objects64) &&
	midx_read_expect 1 62 5 objects64 " large_offsets"
'

test_done
