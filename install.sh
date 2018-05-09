function join {
	local str=""
	for arg in $1; do
		if [ -z $str ]; then
			str="$arg"
		else
			str.=", ""$arg"
		fi
	done
	echo "$str"
}

set -e
CPUS=`grep -c ^processor /proc/cpuinfo`
TOP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_DIR=${TOP_DIR}/source
BUILD_DIR=${TOP_DIR}/build
STATES_DIR=${TOP_DIR}/.states
BINUTILS_SRC_DIR=${SOURCE_DIR}/binutils-2.30
LLVM_SRC_DIR=${SOURCE_DIR}/llvm-3.9
LINUX_SRC_DIR=${SOURCE_DIR}/linux-4.16.7
HUGEPAGE_SRC_DIR=${SOURCE_DIR}/hugepage
BINUTILS_BUILD_DIR=${BUILD_DIR}/binutils
LLVM_BUILD_DIR=${BUILD_DIR}/llvm
PERF_BIN_DIR=${BUILD_DIR}/perf

mkdir -p ${SOURCE_DIR}
mkdir -p ${BUILD_DIR}
mkdir -p ${STATES_DIR}
touch -a ${STATES_DIR}/perf.state
touch -a ${STATES_DIR}/llvm.state
touch -a ${STATES_DIR}/binutils.state
mkdir -p ${BINUTILS_BUILD_DIR}
mkdir -p ${LLVM_BUILD_DIR}
mkdir -p ${PERF_BIN_DIR}

PERF_STATE=$(cat ${STATES_DIR}/perf.state)
LLVM_STATE=$(cat ${STATES_DIR}/llvm.state)
BINUTILS_STATE=$(cat ${STATES_DIR}/binutils.state)

if [ -z "$PERF_STATE" ]; then
	PERF_STATE=0
	echo $PERF_STATE > ${STATES_DIR}/perf.state
fi

if [ -z "$BINUTILS_STATE" ]; then
	BINUTILS_STATE=0
	echo $LLVM_STATE > ${STATES_DIR}/llvm.state
fi

if [ -z "$LLVM_STATE" ]; then
	LLVM_STATE=0
	echo $BINUTILS_STATE > ${STATES_DIR}/binutils.state
fi

echo "downloading base sources..."
if [ "$BINUTILS_STATE" -eq "0" ]; then
	echo "downloading binutils-2.30"
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.xz -P ${SOURCE_DIR} -q
	tar -xf ${SOURCE_DIR}/binutils-2.30.tar.xz -C ${SOURCE_DIR}
	rm ${SOURCE_DIR}/binutils-2.30.tar.xz
	BINUTILS_STATE=1
	echo $BINUTILS_STATE > ${STATES_DIR}/binutils.state
fi

if [ $LLVM_STATE -eq "0" ]; then
	echo "downloading llvm version 3.9 revision 301135"
	svn co http://llvm.org/svn/llvm-project/llvm/branches/release_39/ ${LLVM_SRC_DIR} -q -r 301135
	svn co http://llvm.org/svn/llvm-project/cfe/branches/release_39/ ${LLVM_SRC_DIR}/tools/clang -q -r 301135
	LLVM_STATE=1
	echo $LLVM_STATE > ${STATES_DIR}/llvm.state
fi

if [ $PERF_STATE -eq "0" ]; then
	echo "downloading linux perf tool source"
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.16.7.tar.xz -P ${SOURCE_DIR} -q
	tar -xf ${SOURCE_DIR}/linux-4.16.7.tar.xz -C ${SOURCE_DIR}
	rm ${SOURCE_DIR}/linux-4.16.7.tar.xz
	PERF_STATE=1
	echo $PERF_STATE > ${STATES_DIR}/perf.state
fi

echo "patching...."
if [ $BINUTILS_STATE -eq "1" ]; then
	echo "patching binutils"
	patch -p0 -d ${SOURCE_DIR} < ${TOP_DIR}/patches/binutils.patch
	BINUTILS_STATE=2
	echo $BINUTILS_STATE > ${STATES_DIR}/binutils.state
fi

if [ $LLVM_STATE -eq "1" ]; then
	echo "patching llvm"
	patch -p0 -d ${LLVM_SRC_DIR} < ${TOP_DIR}/patches/llvm.patch
	LLVM_STATE=2
	echo $LLVM_STATE > ${STATES_DIR}/llvm.state
fi

if [ $PERF_STATE -eq "1" ]; then
	echo "patching perf"
	patch -p0 -d ${SOURCE_DIR} < ${TOP_DIR}/patches/perf.patch
	PERF_STATE=2
	echo $PERF_STATE > ${STATES_DIR}/perf.state
fi

echo "building..."
if [ $PERF_STATE -eq "2" ]; then
	echo "building linux perf"
	cd ${LINUX_SRC_DIR}/tools/perf
	make -j${CPUS} > /dev/null
	cp ${LINUX_SRC_DIR}/tools/perf/perf ${PERF_BIN_DIR}/perf
	PERF_STATE=3
	echo $PERF_STATE > ${STATES_DIR}/perf.state
	echo "testing to see if perf works with LBR (last branch record)"
	${PERF_BIN_DIR}/perf record -e cycles -b -o perf-sanity.data -q -- sleep 1
	if [ ! -f perf-sanity.data ]; then
		echo "Failed: OS/Hardware does not support LBR!"
		exit -1
	else
		echo "Success: LBR is supported!"
		rm perf-sanity.data
	fi
fi

if [ $BINUTILS_STATE -eq "2" ]; then
	echo "building binutils"
	cd ${BINUTILS_BUILD_DIR}
	${BINUTILS_SRC_DIR}/configure CXX=g++ CC=gcc --enable-gold --enable-plugins --disable-werror -q
	make all-gold -j$CPUS > /dev/null
	mkdir -p ${BINUTILS_BUILD_DIR}/bin
	ln -sf /bin/true ${BINUTILS_BUILD_DIR}/bin/ranlib
	ln -sf ${BINUTILS_BUILD_DIR}/gold/ld-new ${BINUTILS_BUILD_DIR}/bin/ld
	ln -sf ${BINUTILS_BUILD_DIR}/bfd/libtool ${BINUTILS_BUILD_DIR}/bin/libtool
	BINUTILS_STATE=3
	echo $BINUTILS_STATE > ${STATES_DIR}/binutils.state
fi

if [ $LLVM_STATE -eq "2" ]; then
	echo "building llvm"
	cd ${LLVM_BUILD_DIR}
	cmake ${LLVM_SRC_DIR} -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD=host -DLLVM_ENABLE_CXX1Y=ON -DLLVM_BUILD_TESTS=OFF -DLLVM_BINUTILS_INCDIR=${BINUTILS_SRC_DIR}/include -DLLVM_BUILD_TOOLS=OFF -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ > /dev/null
	make -j${CPUS} --silent
	LLVM_STATE=3
	echo $LLVM_STATE > ${STATES_DIR}/llvm.state
fi


str="Checking if ruby works:"
if [ -z $(command -v ruby) ]; then
	echo $str" No, ruby is not installed! Install it."
	exit
else
	echo $str" Yes, it works!"
fi

str="Checking that the required gems are installed:"
gems=()

set +e
ruby -e "require 'optparse'" &> /dev/null
ec=$?
if [ ! $ec -eq 0 ]; then
	gems+=("optparse")
fi

ruby -e "require 'json'" &> /dev/null
ec=$?
if [ ! $ec -eq 0 ]; then
	gems+=("json")
fi

ruby -e "require 'set'" &> /dev/null
ec=$?
if [ ! $ec -eq 0 ]; then
	gems+=("set")
fi

ruby -e "require 'fileutils'" &> /dev/null
ec=$?
if [ ! $ec -eq 0 ]; then
	gems+=("fileutils")
fi

gems_str=$(join $gems)
if [ -z $gems_str ]; then
	echo "All required ruby gems are installed!"
else
	echo "These required gems: ($gems_str), are not installed!"
	echo -e "\tInstall them by running gem install!"
	exit
fi

ruby -e "require 'graphviz'" &> /dev/null
ec=$?
if [ ! $ec -eq 0 ]; then
	echo $str" Warning: ruby-graphviz gem is not installed!"
	echo -e "\tCFG visualization will not work!"
	echo -e "\tTo fix, install graphviz and its ruby gem:"
	echo -e "\t\tsudo apt-get install ruby-graphviz"
	echo -e "\t\tsudo gem install ruby-graphviz"
fi

echo "building hugepage"
cd ${HUGEPAGE_SRC_DIR}
make
