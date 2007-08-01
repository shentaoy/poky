inherit rootfs_${IMAGE_PKGTYPE}

LICENSE = "MIT"
PACKAGES = ""
RDEPENDS = "${IMAGE_INSTALL}"

export IMAGE_BASENAME = "${PN}"
export PACKAGE_INSTALL = "${IMAGE_INSTALL}"

# We need to recursively follow RDEPENDS and RRECOMMENDS for images
BUILD_ALL_DEPS = "1"
do_rootfs[recrdeptask] = "do_package_write do_deploy do_populate_staging"

# Images are generally built explicitly, do not need to be part of world.
EXCLUDE_FROM_WORLD = "1"

USE_DEVFS ?= "0"

PID = "${@os.getpid()}"

PACKAGE_ARCH = "${MACHINE_ARCH}"

do_rootfs[depends] += "makedevs-native:do_populate_staging fakeroot-native:do_populate_staging"

python () {
    import bb

    deps = bb.data.getVarFlag('do_rootfs', 'depends', d) or ""
    for type in (bb.data.getVar('IMAGE_FSTYPES', d, True) or "").split():
        for dep in ((bb.data.getVar('IMAGE_DEPENDS_%s' % type, d) or "").split() or []):
            deps += " %s:do_populate_staging" % dep
    for dep in (bb.data.getVar('EXTRA_IMAGEDEPENDS', d, True) or "").split():
        deps += " %s:do_populate_staging" % dep
    bb.data.setVarFlag('do_rootfs', 'depends', deps, d)
}

IMAGE_DEVICE_TABLE ?= "${@bb.which(bb.data.getVar('BBPATH', d, 1), 'files/device_table-minimal.txt')}"
IMAGE_POSTPROCESS_COMMAND ?= ""

# some default locales
IMAGE_LINGUAS ?= "en-gb"

LINGUAS_INSTALL = "${@" ".join(map(lambda s: "locale-base-%s" % s, bb.data.getVar('IMAGE_LINGUAS', d, 1).split()))}"

ROOTFS_POSTPROCESS_COMMAND ?= ""

do_rootfs[nostamp] = "1"
do_rootfs[dirs] = "${TOPDIR}"
do_build[nostamp] = "1"

# Must call real_do_rootfs() from inside here, rather than as a separate
# task, so that we have a single fakeroot context for the whole process.
fakeroot do_rootfs () {
	set -x
	rm -rf ${IMAGE_ROOTFS}

	if [ "${USE_DEVFS}" != "1" ]; then
		mkdir -p ${IMAGE_ROOTFS}/dev
		makedevs -r ${IMAGE_ROOTFS} -D ${IMAGE_DEVICE_TABLE}
	fi

	rootfs_${IMAGE_PKGTYPE}_do_rootfs

	rm -f ${IMAGE_ROOTFS}${libdir}/ipkg/lists/oe
	
	${IMAGE_PREPROCESS_COMMAND}
		
	export TOPDIR=${TOPDIR}
	export MACHINE=${MACHINE}

	for type in ${IMAGE_FSTYPES}; do
		if test -z "$FAKEROOTKEY"; then
			fakeroot -i ${TMPDIR}/fakedb.image ${PYTHON} `which bbimage` -t $type -e ${FILE}
		else
			${PYTHON} `which bbimage` -n "${IMAGE_NAME}" -t "$type" -e "${FILE}"
		fi

		cd ${DEPLOY_DIR_IMAGE}/
		rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.$type
		ln -s ${IMAGE_NAME}.rootfs.$type ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.$type
	done

	${IMAGE_POSTPROCESS_COMMAND}
}

log_check() {
	set +x
	for target in $*
	do
		lf_path="${WORKDIR}/temp/log.do_$target.${PID}"
		
		echo "log_check: Using $lf_path as logfile"
		
		if test -e "$lf_path"
		then
			rootfs_${IMAGE_PKGTYPE}_log_check $target $lf_path
		else
			echo "Cannot find logfile [$lf_path]"
		fi
		echo "Logfile is clean"		
	done

	set -x
}

# set '*' as the rootpassword so the images
# can decide if they want it or not

zap_root_password () {
	sed 's%^root:[^:]*:%root:*:%' < ${IMAGE_ROOTFS}/etc/passwd >${IMAGE_ROOTFS}/etc/passwd.new
	mv ${IMAGE_ROOTFS}/etc/passwd.new ${IMAGE_ROOTFS}/etc/passwd	
} 

create_etc_timestamp() {
	date +%2m%2d%2H%2M%Y >${IMAGE_ROOTFS}/etc/timestamp
}

# Turn any symbolic /sbin/init link into a file
remove_init_link () {
	if [ -h ${IMAGE_ROOTFS}/sbin/init ]; then
		LINKFILE=${IMAGE_ROOTFS}`readlink ${IMAGE_ROOTFS}/sbin/init`
		rm ${IMAGE_ROOTFS}/sbin/init
		cp $LINKFILE ${IMAGE_ROOTFS}/sbin/init
	fi
}

make_zimage_symlink_relative () {
	if [ -L ${IMAGE_ROOTFS}/boot/zImage ]; then
		(cd ${IMAGE_ROOTFS}/boot/ && for i in `ls zImage-* | sort`; do ln -sf $i zImage; done)
	fi
}

# export the zap_root_password, create_etc_timestamp and remote_init_link
EXPORT_FUNCTIONS zap_root_password create_etc_timestamp remove_init_link do_rootfs make_zimage_symlink_relative

addtask rootfs before do_build after do_install
