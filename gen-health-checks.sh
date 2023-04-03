#!/bin/sh

usage() {
	echo "$0 ARCH DEVICETYPE"
	exit 0
}

if [ $# -le 1 ];then
	usage
fi

GO=0

STORAGE=http://storage.kernelci.org/
#STORAGE=http://storage.staging.kernelci.org/

LAB=localhost
USER=TOBESET
TOKEN=TOBESET
LABRPC=https://$USER:$TOKEN@ADDRESS/RPC2
FPLAN="baseline"

if [ -e labs ];then
	. $(pwd)/labs
fi

ARCH=$1
shift
case $ARCH in
arm64)
	DEFCONFIG=defconfig
;;
arm)
	DEFCONFIG=multi_v7_defconfig
;;
omap)
	DEFCONFIG=omap2plus_defconfig
	ARCH=arm
;;
ixp4xx)
	DEFCONFIG=ixp4xx_defconfig
	ARCH=arm
;;
sunxi)
	DEFCONFIG=sunxi_defconfig
	ARCH=arm
;;
vex)
	DEFCONFIG=vexpress_defconfig
	ARCH=arm
;;
i386)
	DEFCONFIG=i386_defconfig
;;
x86_64)
	DEFCONFIG=x86_64_defconfig
;;
mips)
	DEFCONFIG=malta_defconfig
;;
arc)
	DEFCONFIG=hsdk_defconfig
;;
tegra)
	ARCH=arm
	DEFCONFIG=tegra_defconfig
;;
riscv64)
	ARCH=riscv
	DEFCONFIG=defconfig
;;
riscv)
	DEFCONFIG=defconfig
;;
sparc)
	DEFCONFIG=sparc64_defconfig
;;
*)
	echo "ERROR: unsupported $ARCH"
	exit 1
;;
esac

case $1 in
da850-lcdk)
	DEFCONFIG=davinci_all_defconfig
;;
bcm2837-rpi-3-b-32)
	DEFCONFIG=bcm2835_defconfig
;;
ox820-cloudengines-pogoplug-series-3)
	DEFCONFIG=oxnas_v6_defconfig
;;
esac

DEVICE_TYPE=$1
shift

echo $1 |grep -q defconfig
if [ $? -eq 0 ];then
	DEFCONFIG=$1
	shift
fi

if [ ! -z "$1" -a "$1" != 'go' -a "$1" != 'dl' ];then
	FPLAN="$1"
	shift
fi

if [ "$1" = 'go' ];then
	GO=1
	shift
fi

if [ "$1" = 'dl' ];then
	GO=2
	shift
fi

if [ ! -z "$1" -a "$1" != 'go' ];then
	FPLAN="$1"
	echo "DEBUG: FPLAN is $FPLAN"
	shift
fi

rm $LAB/*yaml

TREE=stable
BRANCH=linux-5.15.y

#TREE=mainline
#BRANCH=linux-5.5-rc6
#BRANCH=master

TREE=next
BRANCH=master

# panda test
#TREE=lee
#BRANCH=android-3.18-preview

wget -q https://storage.kernelci.org/$TREE/$BRANCH -O laststable || exit $?

case $TREE in
stable)
	GIT_DESCRIBE=$(grep -o v[0-9][0-9a-z\.-]* laststable | grep -v bisect | sort -V | uniq | tail -n1)
;;
lee)
	GIT_DESCRIBE=$(grep -o v[0-9][0-9a-z\.-]* laststable | grep -v bisect | sort -V | uniq | tail -n1)
;;
mainline)
	GIT_DESCRIBE=$(grep -o v[0-9].[0-9]-rc[0-9] laststable | grep -v bisect | sort -V | uniq | tail -n1)
;;
next)
	GIT_DESCRIBE=$(grep -o next-[0-9][0-9]* laststable | grep -v bisect |sort | uniq | tail -n1)
	#GIT_DESCRIBE=next-20221111
;;
*)
	echo "UNKNOWN TREE"
	exit 1
;;
esac

echo "DEBUG: seek health checks in $TREE $BRANCH $GIT_DESCRIBE"

mkdir -p buildout
rm -f buildout/*json

echo "DEBUG: download from $TREE/$BRANCH/$GIT_DESCRIBE/$ARCH/$DEFCONFIG"
wget -qN https://storage.kernelci.org/$TREE/$BRANCH/$GIT_DESCRIBE/$ARCH/$DEFCONFIG/gcc-10/bmeta.json
wget -qN https://storage.kernelci.org/$TREE/$BRANCH/$GIT_DESCRIBE/$ARCH/$DEFCONFIG/gcc-10/artifacts.json
mv bmeta.json buildout/ || exit $?
mv artifacts.json buildout/ || exit $?

CALLBACK="--callback-type kernelci \
	--callback-id kernel-ci-callback \
	--callback-dataset all \
	--callback-url https://api.kernelci.org"

CALLBACK=""

echo "DEBUG: get_lab_info for $LAB"
./kci_test get_lab_info --user $USER --lab-config $LAB --lab-token $TOKEN --lab-json $LAB.json
#./kci_test get_lab_info --user $USER --runtime-config $LAB --runtime-token $TOKEN --runtime-json $LAB.json
if [ $? -ne 0 ];then
	exit 1
fi

echo "DEBUG: gen baseline on $LAB with $USER"
#echo fake
./kci_test generate --storage $STORAGE \
	--install-path buildout \
	--lab-json $LAB.json \
	--lab-config $LAB \
	--plan baseline \
	--output $LAB \
	$CALLBACK \
	--user $USER \
	--lab-token $TOKEN $*
if [ $? -ne 0 ];then
	exit 1
fi
#echo "DEBUG: gen crypto"
#./kci_test generate --storage $STORAGE --bmeta-json bmeta.json --dtbs-json dtbs.json --lab-config $LAB --plan crypto --output $LAB \
#	--user $USER \
#	--lab-token $TOKEN $*
#if [ $? -ne 0 ];then
#	exit 1
#fi
echo "DEBUG: gen fastboot"
./kci_test generate --storage $STORAGE --lab-config $LAB --plan baseline-fastboot --output $LAB \
	--install-path buildout \
	--lab-json $LAB.json \
	--user $USER \
	--lab-token $TOKEN $*
if [ $? -ne 0 ];then
	exit 1
fi
echo "DEBUG: gen qemu for $LAB"
PLAN=baseline_qemu
./kci_test generate --storage $STORAGE --lab-config $LAB --plan $PLAN --output $LAB \
	--install-path buildout \
	--lab-json $LAB.json \
	--user $USER \
	--lab-token $TOKEN $*
if [ $? -ne 0 ];then
	exit 1
fi
echo "DEBUG: gen qemu docker for $LAB"
PLAN=baseline-qemu-docker
./kci_test generate --storage $STORAGE --lab-config $LAB --plan $PLAN --output $LAB \
	--install-path buildout \
	--lab-json $LAB.json \
	--user $USER \
	--lab-token $TOKEN $*
if [ $? -ne 0 ];then
	exit 1
fi
echo "============"
find $LAB
find $LAB |grep $DEVICE_TYPE
if [ $? -ne 0 ];then
	echo "ERROR: cannot find job for $DEVICE_TYPE"
	exit 1
fi
echo "============"

rm $LAB/*gicv2*yaml

echo "DEBUG: seek jobs for $DEVICE_TYPE with $FPLAN"
#rm $LAB/*baseline*
NB=$(find $LAB |grep $DEVICE_TYPE | grep $FPLAN | wc -l)
echo "INFO: Found $NB jobs"
if [ $NB -ne 1 ];then
	echo "ERROR: wrong number of jobs"
	exit 1
fi

mkdir -p $HOME/kernelci-core/submit
rm $HOME/kernelci-core/submit/*yaml
cp $LAB/*$DEVICE_TYPE*$FPLAN* $HOME/kernelci-core/submit/

if [ $GO -eq 1 ];then
	for i in $(seq 1 1)
	do
		./kci_test submit --lab-config $LAB --user $USER --lab-token $TOKEN --jobs $HOME/kernelci-core/submit/*yaml > jobid
		cat jobid
		lavacli --uri $LABRPC jobs wait $(cut -d' ' -f1 jobid)
		lavacli --uri $LABRPC jobs show $(cut -d' ' -f1 jobid) > job-result
		grep Health job-result
		grep -q Health.*Complete job-result
		if [ $? -ne 0 ];then
			exit 1
		fi
	done
fi

if [ $GO -le 1 ];then
	exit 0
fi

if [ ! -e ../lava-healthchecks-binary ];then
	echo "ERROR: missing lava-healthchecks-binary"
	exit 0
fi

NOACT=0
grep storage.kernelci.org $HOME/kernelci-core/submit/* |grep -iE 'url' |\
	grep -v '/$' |\
	sed 's,^.*http,http,' |\
	sort | uniq |
while read line
do
	OLDPATH=$(pwd)
	IPATH=$(dirname $line | sed 's,^http[s]*://[a-z0-9\.]*/,,')
	echo "HANDLE: $IPATH"
	if [ $NOACT -eq 1 ];then
		echo "DEBUG: will create ../lava-healthchecks-binary/$BASEPATH/$IPATH"
		echo "DEBUG: wget $line"
	else
		mkdir -pv ../lava-healthchecks-binary/$BASEPATH/$IPATH
		cd ../lava-healthchecks-binary/$BASEPATH/$IPATH
		wget -N $line
	fi
	cd $OLDPATH
done

sed -i 's,storage.kernelci.org,github.com/montjoie/lava-healthchecks-binary/blob/master,' $HOME/kernelci-core/submit/*
sed -i 's,rootfs.cpio.gz$,rootfs.cpio.gz?raw=true,' $HOME/kernelci-core/submit/*
sed -i 's,\(http.*dtb\)$,\1?raw=true,' $HOME/kernelci-core/submit/*
sed -i 's,\(http.*Image\)$,\1?raw=true,' $HOME/kernelci-core/submit/*
sed -i 's,modules.tar.xz$,modules.tar.xz?raw=true,' $HOME/kernelci-core/submit/*
sed -i 's,http://github.com,https://github.com,' $HOME/kernelci-core/submit/*
sed -i "s,job_name.*,job_name: Health Check for $DEVICE_TYPE with $GIT_DESCRIBE," $HOME/kernelci-core/submit/* || exit 1

cp -v $HOME/kernelci-core/submit/*$DEVICE_TYPE*baseline* $HOME/lava-healthchecks/health-checks/$DEVICE_TYPE.yaml
