#!@PREFIX_PORTAGE_BASH@
# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Hardcoded bash lists are needed for backward compatibility with
# <portage-2.1.4 since they assume that a newly installed version
# of ebuild.sh will work for pkg_postinst, pkg_prerm, and pkg_postrm
# when portage is upgrading itself.

PORTAGE_READONLY_METADATA="DEFINED_PHASES DEPEND DESCRIPTION
	EAPI HOMEPAGE INHERITED IUSE REQUIRED_USE KEYWORDS LICENSE
	PDEPEND PROVIDE RDEPEND RESTRICT SLOT SRC_URI"

PORTAGE_READONLY_VARS="D EBUILD EBUILD_PHASE \
	EBUILD_SH_ARGS ECLASSDIR EMERGE_FROM FILESDIR MERGE_TYPE \
	PM_EBUILD_HOOK_DIR \
	PORTAGE_ACTUAL_DISTDIR PORTAGE_ARCHLIST PORTAGE_BASHRC  \
	PORTAGE_BINPKG_FILE PORTAGE_BINPKG_TAR_OPTS PORTAGE_BINPKG_TMPFILE \
	PORTAGE_BIN_PATH PORTAGE_BUILDDIR PORTAGE_BUNZIP2_COMMAND \
	PORTAGE_BZIP2_COMMAND PORTAGE_COLORMAP PORTAGE_CONFIGROOT \
	PORTAGE_DEBUG PORTAGE_DEPCACHEDIR PORTAGE_EBUILD_EXIT_FILE \
	PORTAGE_GID PORTAGE_GRPNAME PORTAGE_INST_GID PORTAGE_INST_UID \
	PORTAGE_IPC_DAEMON PORTAGE_IUSE PORTAGE_LOG_FILE \
	PORTAGE_MUTABLE_FILTERED_VARS PORTAGE_PYM_PATH PORTAGE_PYTHON \
	PORTAGE_READONLY_METADATA PORTAGE_READONLY_VARS \
	PORTAGE_REPO_NAME PORTAGE_RESTRICT PORTAGE_SANDBOX_COMPAT_LEVEL \
	PORTAGE_SAVED_READONLY_VARS PORTAGE_SIGPIPE_STATUS \
	PORTAGE_TMPDIR PORTAGE_UPDATE_ENV PORTAGE_USERNAME \
	PORTAGE_VERBOSE PORTAGE_WORKDIR_MODE PORTDIR PORTDIR_OVERLAY \
	PROFILE_PATHS REPLACING_VERSIONS REPLACED_BY_VERSION T WORKDIR \
	__PORTAGE_TEST_EPREFIX ED EROOT"

PORTAGE_SAVED_READONLY_VARS="A CATEGORY P PF PN PR PV PVR"

# Variables that portage sets but doesn't mark readonly.
# In order to prevent changed values from causing unexpected
# interference, they are filtered out of the environment when
# it is saved or loaded (any mutations do not persist).
PORTAGE_MUTABLE_FILTERED_VARS="AA HOSTNAME"

# @FUNCTION: filter_readonly_variables
# @DESCRIPTION: [--filter-sandbox] [--allow-extra-vars]
# Read an environment from stdin and echo to stdout while filtering variables
# with names that are known to cause interference:
#
#   * some specific variables for which bash does not allow assignment
#   * some specific variables that affect portage or sandbox behavior
#   * variable names that begin with a digit or that contain any
#     non-alphanumeric characters that are not be supported by bash
#
# --filter-sandbox causes all SANDBOX_* variables to be filtered, which
# is only desired in certain cases, such as during preprocessing or when
# saving environment.bz2 for a binary or installed package.
#
# --filter-features causes the special FEATURES variable to be filtered.
# Generally, we want it to persist between phases since the user might
# want to modify it via bashrc to enable things like splitdebug and
# installsources for specific packages. They should be able to modify it
# in pre_pkg_setup() and have it persist all the way through the install
# phase. However, if FEATURES exist inside environment.bz2 then they
# should be overridden by current settings.
#
# --filter-locale causes locale related variables such as LANG and LC_*
# variables to be filtered. These variables should persist between phases,
# in case they are modified by the ebuild. However, the current user
# settings should be used when loading the environment from a binary or
# installed package.
#
# --filter-path causes the PATH variable to be filtered. This variable
# should persist between phases, in case it is modified by the ebuild.
# However, old settings should be overridden when loading the
# environment from a binary or installed package.
#
# ---allow-extra-vars causes some extra vars to be allowd through, such
# as ${PORTAGE_SAVED_READONLY_VARS} and ${PORTAGE_MUTABLE_FILTERED_VARS}.
#
# In bash-3.2_p20+ an attempt to assign BASH_*, FUNCNAME, GROUPS or any
# readonly variable cause the shell to exit while executing the "source"
# builtin command. To avoid this problem, this function filters those
# variables out and discards them. See bug #190128.
filter_readonly_variables() {
	local x filtered_vars
	local readonly_bash_vars="BASHOPTS BASHPID DIRSTACK EUID
		FUNCNAME GROUPS PIPESTATUS PPID SHELLOPTS UID"
	local bash_misc_vars="BASH BASH_.* COMP_WORDBREAKS HISTCMD
		HISTFILE HOSTNAME HOSTTYPE IFS LINENO MACHTYPE OLDPWD
		OPTERR OPTIND OSTYPE POSIXLY_CORRECT PS4 PWD RANDOM
		SECONDS SHELL SHLVL _"
	local filtered_sandbox_vars="SANDBOX_ACTIVE SANDBOX_BASHRC
		SANDBOX_DEBUG_LOG SANDBOX_DISABLED SANDBOX_LIB
		SANDBOX_LOG SANDBOX_ON"
	local misc_garbage_vars="_portage_filter_opts"
	filtered_vars="$readonly_bash_vars $bash_misc_vars
		$PORTAGE_READONLY_VARS $misc_garbage_vars"

	# Don't filter/interfere with prefix variables unless they are
	# supported by the current EAPI.
	case "${EAPI:-0}" in
		0|1|2)
			[[ " ${FEATURES} " == *" force-prefix "* ]] && \
				filtered_vars+=" ED EPREFIX EROOT"
			;;
		*)
			filtered_vars+=" ED EPREFIX EROOT"
			;;
	esac

	if has --filter-sandbox $* ; then
		filtered_vars="${filtered_vars} SANDBOX_.*"
	else
		filtered_vars="${filtered_vars} ${filtered_sandbox_vars}"
	fi
	if has --filter-features $* ; then
		filtered_vars="${filtered_vars} FEATURES PORTAGE_FEATURES"
	fi
	if has --filter-path $* ; then
		filtered_vars+=" PATH"
	fi
	if has --filter-locale $* ; then
		filtered_vars+=" LANG LC_ALL LC_COLLATE
			LC_CTYPE LC_MESSAGES LC_MONETARY
			LC_NUMERIC LC_PAPER LC_TIME"
	fi
	if ! has --allow-extra-vars $* ; then
		filtered_vars="
			${filtered_vars}
			${PORTAGE_SAVED_READONLY_VARS}
			${PORTAGE_MUTABLE_FILTERED_VARS}
		"
	fi

	"${PORTAGE_PYTHON:-@PREFIX_PORTAGE_PYTHON@}" "${PORTAGE_BIN_PATH}"/filter-bash-environment.py "${filtered_vars}" || die "filter-bash-environment.py failed"
}

# @FUNCTION: preprocess_ebuild_env
# @DESCRIPTION:
# Filter any readonly variables from ${T}/environment, source it, and then
# save it via save_ebuild_env(). This process should be sufficient to prevent
# any stale variables or functions from an arbitrary environment from
# interfering with the current environment. This is useful when an existing
# environment needs to be loaded from a binary or installed package.
preprocess_ebuild_env() {
	local _portage_filter_opts="--filter-features --filter-locale --filter-path --filter-sandbox"

	# If environment.raw is present, this is a signal from the python side,
	# indicating that the environment may contain stale FEATURES and
	# SANDBOX_{DENY,PREDICT,READ,WRITE} variables that should be filtered out.
	# Otherwise, we don't need to filter the environment.
	[ -f "${T}/environment.raw" ] || return 0

	filter_readonly_variables $_portage_filter_opts < "${T}"/environment \
		>> "$T/environment.filtered" || return $?
	unset _portage_filter_opts
	mv "${T}"/environment.filtered "${T}"/environment || return $?
	rm -f "${T}/environment.success" || return $?
	# WARNING: Code inside this subshell should avoid making assumptions
	# about variables or functions after source "${T}"/environment has been
	# called. Any variables that need to be relied upon should already be
	# filtered out above.
	(
		export SANDBOX_ON=1
		source "${T}/environment" || exit $?
		# We have to temporarily disable sandbox since the
		# SANDBOX_{DENY,READ,PREDICT,WRITE} values we've just loaded
		# may be unusable (triggering in spurious sandbox violations)
		# until we've merged them with our current values.
		export SANDBOX_ON=0

		# It's remotely possible that save_ebuild_env() has been overridden
		# by the above source command. To protect ourselves, we override it
		# here with our own version. ${PORTAGE_BIN_PATH} is safe to use here
		# because it's already filtered above.
		source "${PORTAGE_BIN_PATH}/save-ebuild-env.sh" || exit $?

		# Rely on save_ebuild_env() to filter out any remaining variables
		# and functions that could interfere with the current environment.
		save_ebuild_env || exit $?
		>> "$T/environment.success" || exit $?
	) > "${T}/environment.filtered"
	local retval
	if [ -e "${T}/environment.success" ] ; then
		filter_readonly_variables --filter-features < \
			"${T}/environment.filtered" > "${T}/environment"
		retval=$?
	else
		retval=1
	fi
	rm -f "${T}"/environment.{filtered,raw,success}
	return ${retval}
}

ebuild_phase() {
	declare -F "$1" >/dev/null && qa_call $1
}

ebuild_phase_with_hooks() {
	local x phase_name=${1}
	for x in {pre_,,post_}${phase_name} ; do
		ebuild_phase ${x}
	done
}

dyn_pretend() {
	if [[ -e $PORTAGE_BUILDDIR/.pretended ]] ; then
		vecho ">>> It appears that '$PF' is already pretended; skipping."
		vecho ">>> Remove '$PORTAGE_BUILDDIR/.pretended' to force pretend."
		return 0
	fi
	ebuild_phase pre_pkg_pretend
	ebuild_phase pkg_pretend
	>> "$PORTAGE_BUILDDIR/.pretended" || \
		die "Failed to create $PORTAGE_BUILDDIR/.pretended"
	ebuild_phase post_pkg_pretend
}

dyn_setup() {
	if [[ -e $PORTAGE_BUILDDIR/.setuped ]] ; then
		vecho ">>> It appears that '$PF' is already setup; skipping."
		vecho ">>> Remove '$PORTAGE_BUILDDIR/.setuped' to force setup."
		return 0
	fi
	ebuild_phase pre_pkg_setup
	ebuild_phase pkg_setup
	>> "$PORTAGE_BUILDDIR/.setuped" || \
		die "Failed to create $PORTAGE_BUILDDIR/.setuped"
	ebuild_phase post_pkg_setup
}

dyn_unpack() {
	if [[ -f ${PORTAGE_BUILDDIR}/.unpacked ]] ; then
		vecho ">>> WORKDIR is up-to-date, keeping..."
		return 0
	fi
	if [ ! -d "${WORKDIR}" ]; then
		install -m${PORTAGE_WORKDIR_MODE:-0700} -d "${WORKDIR}" || die "Failed to create dir '${WORKDIR}'"
	fi
	cd "${WORKDIR}" || die "Directory change failed: \`cd '${WORKDIR}'\`"
	ebuild_phase pre_src_unpack
	vecho ">>> Unpacking source..."
	ebuild_phase src_unpack
	>> "$PORTAGE_BUILDDIR/.unpacked" || \
		die "Failed to create $PORTAGE_BUILDDIR/.unpacked"
	vecho ">>> Source unpacked in ${WORKDIR}"
	ebuild_phase post_src_unpack
}

dyn_clean() {
	if [ -z "${PORTAGE_BUILDDIR}" ]; then
		echo "Aborting clean phase because PORTAGE_BUILDDIR is unset!"
		return 1
	elif [ ! -d "${PORTAGE_BUILDDIR}" ] ; then
		return 0
	fi
	if has chflags $FEATURES ; then
		chflags -R noschg,nouchg,nosappnd,nouappnd "${PORTAGE_BUILDDIR}"
		chflags -R nosunlnk,nouunlnk "${PORTAGE_BUILDDIR}" 2>/dev/null
	fi

	rm -rf "${PORTAGE_BUILDDIR}/image" "${PORTAGE_BUILDDIR}/homedir"
	rm -f "${PORTAGE_BUILDDIR}/.installed"

	if [[ $EMERGE_FROM = binary ]] || \
		! has keeptemp $FEATURES && ! has keepwork $FEATURES ; then
		rm -rf "${T}"
	fi

	if [[ $EMERGE_FROM = binary ]] || ! has keepwork $FEATURES; then
		rm -f "$PORTAGE_BUILDDIR"/.{ebuild_changed,logid,pretended,setuped,unpacked,prepared} \
			"$PORTAGE_BUILDDIR"/.{configured,compiled,tested,packaged} \
			"$PORTAGE_BUILDDIR"/.die_hooks \
			"$PORTAGE_BUILDDIR"/.ipc_{in,out,lock} \
			"$PORTAGE_BUILDDIR"/.exit_status

		rm -rf "${PORTAGE_BUILDDIR}/build-info"
		rm -rf "${WORKDIR}"
	fi

	if [ -f "${PORTAGE_BUILDDIR}/.unpacked" ]; then
		find "${PORTAGE_BUILDDIR}" -type d ! -regex "^${WORKDIR}" | sort -r | tr "\n" "\0" | $XARGS -0 rmdir &>/dev/null
	fi

	# do not bind this to doebuild defined DISTDIR; don't trust doebuild, and if mistakes are made it'll
	# result in it wiping the users distfiles directory (bad).
	rm -rf "${PORTAGE_BUILDDIR}/distdir"

	# Some kernels, such as Solaris, return EINVAL when an attempt
	# is made to remove the current working directory.
	cd "$PORTAGE_BUILDDIR"/../..
	rmdir "$PORTAGE_BUILDDIR" 2>/dev/null

	true
}

abort_handler() {
	local msg
	if [ "$2" != "fail" ]; then
		msg="${EBUILD}: ${1} aborted; exiting."
	else
		msg="${EBUILD}: ${1} failed; exiting."
	fi
	echo
	echo "$msg"
	echo
	eval ${3}
	#unset signal handler
	trap - SIGINT SIGQUIT
}

abort_prepare() {
	abort_handler src_prepare $1
	rm -f "$PORTAGE_BUILDDIR/.prepared"
	exit 1
}

abort_configure() {
	abort_handler src_configure $1
	rm -f "$PORTAGE_BUILDDIR/.configured"
	exit 1
}

abort_compile() {
	abort_handler "src_compile" $1
	rm -f "${PORTAGE_BUILDDIR}/.compiled"
	exit 1
}

abort_test() {
	abort_handler "dyn_test" $1
	rm -f "${PORTAGE_BUILDDIR}/.tested"
	exit 1
}

abort_install() {
	abort_handler "src_install" $1
	rm -rf "${PORTAGE_BUILDDIR}/image"
	exit 1
}

has_phase_defined_up_to() {
	local phase
	for phase in unpack prepare configure compile install; do
		has ${phase} ${DEFINED_PHASES} && return 0
		[[ ${phase} == $1 ]] && return 1
	done
	# We shouldn't actually get here
	return 1
}

dyn_prepare() {

	if [[ -e $PORTAGE_BUILDDIR/.prepared ]] ; then
		vecho ">>> It appears that '$PF' is already prepared; skipping."
		vecho ">>> Remove '$PORTAGE_BUILDDIR/.prepared' to force prepare."
		return 0
	fi

	if [[ -d $S ]] ; then
		cd "${S}"
	elif has $EAPI 0 1 2 3 3_pre2 ; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! has_phase_defined_up_to prepare; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap abort_prepare SIGINT SIGQUIT

	ebuild_phase pre_src_prepare
	vecho ">>> Preparing source in $PWD ..."
	ebuild_phase src_prepare
	>> "$PORTAGE_BUILDDIR/.prepared" || \
		die "Failed to create $PORTAGE_BUILDDIR/.prepared"
	vecho ">>> Source prepared."
	ebuild_phase post_src_prepare

	trap - SIGINT SIGQUIT
}

dyn_configure() {

	if [[ -e $PORTAGE_BUILDDIR/.configured ]] ; then
		vecho ">>> It appears that '$PF' is already configured; skipping."
		vecho ">>> Remove '$PORTAGE_BUILDDIR/.configured' to force configuration."
		return 0
	fi

	if [[ -d $S ]] ; then
		cd "${S}"
	elif has $EAPI 0 1 2 3 3_pre2 ; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! has_phase_defined_up_to configure; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap abort_configure SIGINT SIGQUIT

	ebuild_phase pre_src_configure

	vecho ">>> Configuring source in $PWD ..."
	ebuild_phase src_configure
	>> "$PORTAGE_BUILDDIR/.configured" || \
		die "Failed to create $PORTAGE_BUILDDIR/.configured"
	vecho ">>> Source configured."

	ebuild_phase post_src_configure

	trap - SIGINT SIGQUIT
}

dyn_compile() {

	if [[ -e $PORTAGE_BUILDDIR/.compiled ]] ; then
		vecho ">>> It appears that '${PF}' is already compiled; skipping."
		vecho ">>> Remove '$PORTAGE_BUILDDIR/.compiled' to force compilation."
		return 0
	fi

	if [[ -d $S ]] ; then
		cd "${S}"
	elif has $EAPI 0 1 2 3 3_pre2 ; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! has_phase_defined_up_to compile; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap abort_compile SIGINT SIGQUIT

	if has distcc $FEATURES && has distcc-pump $FEATURES ; then
		if [[ -z $INCLUDE_SERVER_PORT ]] || [[ ! -w $INCLUDE_SERVER_PORT ]] ; then
			eval $(pump --startup)
			trap "pump --shutdown" EXIT
		fi
	fi

	ebuild_phase pre_src_compile

	vecho ">>> Compiling source in $PWD ..."
	ebuild_phase src_compile
	>> "$PORTAGE_BUILDDIR/.compiled" || \
		die "Failed to create $PORTAGE_BUILDDIR/.compiled"
	vecho ">>> Source compiled."

	ebuild_phase post_src_compile

	trap - SIGINT SIGQUIT
}

dyn_test() {

	if [[ -e $PORTAGE_BUILDDIR/.tested ]] ; then
		vecho ">>> It appears that ${PN} has already been tested; skipping."
		vecho ">>> Remove '${PORTAGE_BUILDDIR}/.tested' to force test."
		return
	fi

	if [ "${EBUILD_FORCE_TEST}" == "1" ] ; then
		# If USE came from ${T}/environment then it might not have USE=test
		# like it's supposed to here.
		! has test ${USE} && export USE="${USE} test"
	fi

	trap "abort_test" SIGINT SIGQUIT
	if [ -d "${S}" ]; then
		cd "${S}"
	else
		cd "${WORKDIR}"
	fi

	if ! has test $FEATURES && [ "${EBUILD_FORCE_TEST}" != "1" ]; then
		vecho ">>> Test phase [not enabled]: ${CATEGORY}/${PF}"
	elif has test $RESTRICT; then
		einfo "Skipping make test/check due to ebuild restriction."
		vecho ">>> Test phase [explicitly disabled]: ${CATEGORY}/${PF}"
	else
		local save_sp=${SANDBOX_PREDICT}
		addpredict /
		ebuild_phase pre_src_test
		ebuild_phase src_test
		>> "$PORTAGE_BUILDDIR/.tested" || \
			die "Failed to create $PORTAGE_BUILDDIR/.tested"
		ebuild_phase post_src_test
		SANDBOX_PREDICT=${save_sp}
	fi

	trap - SIGINT SIGQUIT
}

dyn_install() {
	[ -z "$PORTAGE_BUILDDIR" ] && die "${FUNCNAME}: PORTAGE_BUILDDIR is unset"
	if has noauto $FEATURES ; then
		rm -f "${PORTAGE_BUILDDIR}/.installed"
	elif [[ -e $PORTAGE_BUILDDIR/.installed ]] ; then
		vecho ">>> It appears that '${PF}' is already installed; skipping."
		vecho ">>> Remove '${PORTAGE_BUILDDIR}/.installed' to force install."
		return 0
	fi
	trap "abort_install" SIGINT SIGQUIT
	ebuild_phase pre_src_install

	_x=${ED}
	[[ " ${FEATURES} " == *" force-prefix "* ]] || \
		case "$EAPI" in 0|1|2) _x=${D} ;; esac
	rm -rf "${D}"
	mkdir -p "${_x}"
	unset _x

	if [[ -d $S ]] ; then
		cd "${S}"
	elif has $EAPI 0 1 2 3 3_pre2 ; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! has_phase_defined_up_to install; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	vecho
	vecho ">>> Install ${PF} into ${D} category ${CATEGORY}"
	#our custom version of libtool uses $S and $D to fix
	#invalid paths in .la files
	export S D

	# Reset exeinto(), docinto(), insinto(), and into() state variables
	# in case the user is running the install phase multiple times
	# consecutively via the ebuild command.
	export DESTTREE=/usr
	export INSDESTTREE=""
	export _E_EXEDESTTREE_=""
	export _E_DOCDESTTREE_=""

	ebuild_phase src_install
	>> "$PORTAGE_BUILDDIR/.installed" || \
		die "Failed to create $PORTAGE_BUILDDIR/.installed"
	vecho ">>> Completed installing ${PF} into ${D}"
	vecho
	ebuild_phase post_src_install

	cd "${PORTAGE_BUILDDIR}"/build-info
	set -f
	local f x
	IFS=$' \t\n\r'
	for f in CATEGORY DEFINED_PHASES FEATURES INHERITED IUSE \
		PF PKGUSE SLOT KEYWORDS HOMEPAGE DESCRIPTION ; do
		x=$(echo -n ${!f})
		[[ -n $x ]] && echo "$x" > $f
	done
	if [[ $CATEGORY != virtual ]] ; then
		for f in ASFLAGS CBUILD CC CFLAGS CHOST CTARGET CXX \
			CXXFLAGS EXTRA_ECONF EXTRA_EINSTALL EXTRA_MAKE \
			LDFLAGS LIBCFLAGS LIBCXXFLAGS ; do
			x=$(echo -n ${!f})
			[[ -n $x ]] && echo "$x" > $f
		done
	fi
	echo "${USE}"       > USE
	echo "${EAPI:-0}"   > EAPI
<<<<<<< HEAD
	echo "${EPREFIX}"   > EPREFIX
=======

	# Save EPREFIX, since it makes it easy to use chpathtool to
	# adjust the content of a binary package so that it will
	# work in a different EPREFIX from the one is was built for.
	case "${EAPI:-0}" in
		0|1|2)
			[[ " ${FEATURES} " == *" force-prefix "* ]] && \
				[ -n "${EPREFIX}" ] && echo "${EPREFIX}" > EPREFIX
			;;
		*)
			[ -n "${EPREFIX}" ] && echo "${EPREFIX}" > EPREFIX
			;;
	esac

>>>>>>> overlays-gentoo-org/master
	set +f

	# local variables can leak into the saved environment.
	unset f

	save_ebuild_env --exclude-init-phases | filter_readonly_variables \
		--filter-path --filter-sandbox --allow-extra-vars > environment
	assert "save_ebuild_env failed"

	${PORTAGE_BZIP2_COMMAND} -f9 environment

	cp "${EBUILD}" "${PF}.ebuild"
	[ -n "${PORTAGE_REPO_NAME}" ]  && echo "${PORTAGE_REPO_NAME}" > repository
	if has nostrip ${FEATURES} ${RESTRICT} || has strip ${RESTRICT}
	then
		>> DEBUGBUILD
	fi
	trap - SIGINT SIGQUIT
}

dyn_preinst() {
	if [ -z "${D}" ]; then
		eerror "${FUNCNAME}: D is unset"
		return 1
	fi
	ebuild_phase_with_hooks pkg_preinst
}

dyn_help() {
	echo
	echo "Portage"
	echo "Copyright 1999-2010 Gentoo Foundation"
	echo
	echo "How to use the ebuild command:"
	echo
	echo "The first argument to ebuild should be an existing .ebuild file."
	echo
	echo "One or more of the following options can then be specified.  If more"
	echo "than one option is specified, each will be executed in order."
	echo
	echo "  help        : show this help screen"
	echo "  pretend     : execute package specific pretend actions"
	echo "  setup       : execute package specific setup actions"
	echo "  fetch       : download source archive(s) and patches"
	echo "  digest      : create a manifest file for the package"
	echo "  manifest    : create a manifest file for the package"
	echo "  unpack      : unpack sources (auto-dependencies if needed)"
	echo "  prepare     : prepare sources (auto-dependencies if needed)"
	echo "  configure   : configure sources (auto-fetch/unpack if needed)"
	echo "  compile     : compile sources (auto-fetch/unpack/configure if needed)"
	echo "  test        : test package (auto-fetch/unpack/configure/compile if needed)"
	echo "  preinst     : execute pre-install instructions"
	echo "  postinst    : execute post-install instructions"
	echo "  install     : install the package to the temporary install directory"
	echo "  qmerge      : merge image into live filesystem, recording files in db"
	echo "  merge       : do fetch, unpack, compile, install and qmerge"
	echo "  prerm       : execute pre-removal instructions"
	echo "  postrm      : execute post-removal instructions"
	echo "  unmerge     : remove package from live filesystem"
	echo "  config      : execute package specific configuration actions"
	echo "  package     : create a tarball package in ${PKGDIR}/All"
	echo "  rpm         : build a RedHat RPM package"
	echo "  clean       : clean up all source and temporary files"
	echo
	echo "The following settings will be used for the ebuild process:"
	echo
	echo "  package     : ${PF}"
	echo "  slot        : ${SLOT}"
	echo "  category    : ${CATEGORY}"
	echo "  description : ${DESCRIPTION}"
	echo "  system      : ${CHOST}"
	echo "  c flags     : ${CFLAGS}"
	echo "  c++ flags   : ${CXXFLAGS}"
	echo "  make flags  : ${MAKEOPTS}"
	echo -n "  build mode  : "
	if has nostrip ${FEATURES} ${RESTRICT} || has strip ${RESTRICT} ;
	then
		echo "debug (large)"
	else
		echo "production (stripped)"
	fi
	echo "  merge to    : ${ROOT}"
	echo "  offset      : ${EPREFIX}"
	echo
	if [ -n "$USE" ]; then
		echo "Additionally, support for the following optional features will be enabled:"
		echo
		echo "  ${USE}"
	fi
	echo
}

# @FUNCTION: _ebuild_arg_to_phase
# @DESCRIPTION:
# Translate a known ebuild(1) argument into the precise
# name of it's corresponding ebuild phase.
_ebuild_arg_to_phase() {
	[ $# -ne 2 ] && die "expected exactly 2 args, got $#: $*"
	local eapi=$1
	local arg=$2
	local phase_func=""

	case "$arg" in
		pretend)
			! has $eapi 0 1 2 3 3_pre2 && \
				phase_func=pkg_pretend
			;;
		setup)
			phase_func=pkg_setup
			;;
		nofetch)
			phase_func=pkg_nofetch
			;;
		unpack)
			phase_func=src_unpack
			;;
		prepare)
			! has $eapi 0 1 && \
				phase_func=src_prepare
			;;
		configure)
			! has $eapi 0 1 && \
				phase_func=src_configure
			;;
		compile)
			phase_func=src_compile
			;;
		test)
			phase_func=src_test
			;;
		install)
			phase_func=src_install
			;;
		preinst)
			phase_func=pkg_preinst
			;;
		postinst)
			phase_func=pkg_postinst
			;;
		prerm)
			phase_func=pkg_prerm
			;;
		postrm)
			phase_func=pkg_postrm
			;;
	esac

	[[ -z $phase_func ]] && return 1
	echo "$phase_func"
	return 0
}

_ebuild_phase_funcs() {
	[ $# -ne 2 ] && die "expected exactly 2 args, got $#: $*"
	local eapi=$1
	local phase_func=$2
	local default_phases="pkg_nofetch src_unpack src_prepare src_configure
		src_compile src_install src_test"
	local x y default_func=""

	for x in pkg_nofetch src_unpack src_test ; do
		declare -F $x >/dev/null || \
			eval "$x() { _eapi0_$x \"\$@\" ; }"
	done

	case $eapi in

		0|1)

			if ! declare -F src_compile >/dev/null ; then
				case $eapi in
					0)
						src_compile() { _eapi0_src_compile "$@" ; }
						;;
					*)
						src_compile() { _eapi1_src_compile "$@" ; }
						;;
				esac
			fi

			for x in $default_phases ; do
				eval "default_$x() {
					die \"default_$x() is not supported with EAPI='$eapi' during phase $phase_func\"
				}"
			done

			eval "default() {
				die \"default() is not supported with EAPI='$eapi' during phase $phase_func\"
			}"

			;;

		*)

			declare -F src_configure >/dev/null || \
				src_configure() { _eapi2_src_configure "$@" ; }

			declare -F src_compile >/dev/null || \
				src_compile() { _eapi2_src_compile "$@" ; }

			has $eapi 2 3 3_pre2 || declare -F src_install >/dev/null || \
				src_install() { _eapi4_src_install "$@" ; }

			if has $phase_func $default_phases ; then

				_eapi2_pkg_nofetch   () { _eapi0_pkg_nofetch          "$@" ; }
				_eapi2_src_unpack    () { _eapi0_src_unpack           "$@" ; }
				_eapi2_src_prepare   () { true                             ; }
				_eapi2_src_test      () { _eapi0_src_test             "$@" ; }
				_eapi2_src_install   () { die "$FUNCNAME is not supported" ; }

				for x in $default_phases ; do
					eval "default_$x() { _eapi2_$x \"\$@\" ; }"
				done

				eval "default() { _eapi2_$phase_func \"\$@\" ; }"

				case $eapi in
					2|3)
						;;
					*)
						eval "default_src_install() { _eapi4_src_install \"\$@\" ; }"
						[[ $phase_func = src_install ]] && \
							eval "default() { _eapi4_$phase_func \"\$@\" ; }"
						;;
				esac

			else

				for x in $default_phases ; do
					eval "default_$x() {
						die \"default_$x() is not supported in phase $default_func\"
					}"
				done

				eval "default() {
					die \"default() is not supported with EAPI='$eapi' during phase $phase_func\"
				}"

			fi

			;;
	esac
}

ebuild_main() {

	# Subshell/helper die support (must export for the die helper).
	# Since this function is typically executed in a subshell,
	# setup EBUILD_MASTER_PID to refer to the current $BASHPID,
	# which seems to give the best results when further
	# nested subshells call die.
	export EBUILD_MASTER_PID=$BASHPID
	trap 'exit 1' SIGTERM

	#a reasonable default for $S
	[[ -z ${S} ]] && export S=${WORKDIR}/${P}

	if [[ -s $SANDBOX_LOG ]] ; then
		# We use SANDBOX_LOG to check for sandbox violations,
		# so we ensure that there can't be a stale log to
		# interfere with our logic.
		local x=
		if [[ -n SANDBOX_ON ]] ; then
			x=$SANDBOX_ON
			export SANDBOX_ON=0
		fi

		rm -f "$SANDBOX_LOG" || \
			die "failed to remove stale sandbox log: '$SANDBOX_LOG'"

		if [[ -n $x ]] ; then
			export SANDBOX_ON=$x
		fi
		unset x
	fi

	# Force configure scripts that automatically detect ccache to
	# respect FEATURES="-ccache".
	has ccache $FEATURES || export CCACHE_DISABLE=1

	local phase_func=$(_ebuild_arg_to_phase "$EAPI" "$EBUILD_PHASE")
	[[ -n $phase_func ]] && _ebuild_phase_funcs "$EAPI" "$phase_func"
	unset phase_func

	source_all_bashrcs

	case ${1} in
	nofetch)
		ebuild_phase_with_hooks pkg_nofetch
		;;
	prerm|postrm|postinst|config|info)
		if has "${1}" config info && \
			! declare -F "pkg_${1}" >/dev/null ; then
			ewarn  "pkg_${1}() is not defined: '${EBUILD##*/}'"
		fi
		export SANDBOX_ON="0"
		if [ "${PORTAGE_DEBUG}" != "1" ] || [ "${-/x/}" != "$-" ]; then
			ebuild_phase_with_hooks pkg_${1}
		else
			set -x
			ebuild_phase_with_hooks pkg_${1}
			set +x
		fi
		if [[ $EBUILD_PHASE == postinst ]] && [[ -n $PORTAGE_UPDATE_ENV ]]; then
			# Update environment.bz2 in case installation phases
			# need to pass some variables to uninstallation phases.
			save_ebuild_env --exclude-init-phases | \
				filter_readonly_variables --filter-path \
				--filter-sandbox --allow-extra-vars \
				| ${PORTAGE_BZIP2_COMMAND} -c -f9 > "$PORTAGE_UPDATE_ENV"
			assert "save_ebuild_env failed"
		fi
		;;
	unpack|prepare|configure|compile|test|clean|install)
		if [[ ${SANDBOX_DISABLED:-0} = 0 ]] ; then
			export SANDBOX_ON="1"
		else
			export SANDBOX_ON="0"
		fi

		case "${1}" in
		configure|compile)

			local x
			for x in ASFLAGS CCACHE_DIR CCACHE_SIZE \
				CFLAGS CXXFLAGS LDFLAGS LIBCFLAGS LIBCXXFLAGS ; do
				[[ ${!x+set} = set ]] && export $x
			done
			unset x

			has distcc $FEATURES && [[ -n $DISTCC_DIR ]] && \
				[[ ${SANDBOX_WRITE/$DISTCC_DIR} = $SANDBOX_WRITE ]] && \
				addwrite "$DISTCC_DIR"

			x=LIBDIR_$ABI
			[ -z "$PKG_CONFIG_PATH" -a -n "$ABI" -a -n "${!x}" ] && \
				export PKG_CONFIG_PATH=/usr/${!x}/pkgconfig

			if has noauto $FEATURES && \
				[[ ! -f $PORTAGE_BUILDDIR/.unpacked ]] ; then
				echo
				echo "!!! We apparently haven't unpacked..." \
					"This is probably not what you"
				echo "!!! want to be doing... You are using" \
					"FEATURES=noauto so I'll assume"
				echo "!!! that you know what you are doing..." \
					"You have 5 seconds to abort..."
				echo

				local x
				for x in 1 2 3 4 5 6 7 8; do
					LC_ALL=C sleep 0.25
				done

				sleep 3
			fi

			cd "$PORTAGE_BUILDDIR"
			if [ ! -d build-info ] ; then
				mkdir build-info
				cp "$EBUILD" "build-info/$PF.ebuild"
			fi

			#our custom version of libtool uses $S and $D to fix
			#invalid paths in .la files
			export S D

			;;
		esac

		if [ "${PORTAGE_DEBUG}" != "1" ] || [ "${-/x/}" != "$-" ]; then
			dyn_${1}
		else
			set -x
			dyn_${1}
			set +x
		fi
		export SANDBOX_ON="0"
		;;
	help|pretend|setup|preinst)
		#pkg_setup needs to be out of the sandbox for tmp file creation;
		#for example, awking and piping a file in /tmp requires a temp file to be created
		#in /etc.  If pkg_setup is in the sandbox, both our lilo and apache ebuilds break.
		export SANDBOX_ON="0"
		if [ "${PORTAGE_DEBUG}" != "1" ] || [ "${-/x/}" != "$-" ]; then
			dyn_${1}
		else
			set -x
			dyn_${1}
			set +x
		fi
		;;
	_internal_test)
		;;
	*)
		export SANDBOX_ON="1"
		echo "Unrecognized arg '${1}'"
		echo
		dyn_help
		exit 1
		;;
	esac

	# Save the env only for relevant phases.
	if ! has "${1}" clean help info nofetch ; then
		umask 002
		save_ebuild_env | filter_readonly_variables \
			--filter-features > "$T/environment"
		assert "save_ebuild_env failed"
		chown portage:portage "$T/environment" &>/dev/null
		chmod g+w "$T/environment" &>/dev/null
	fi
	[[ -n $PORTAGE_EBUILD_EXIT_FILE ]] && > "$PORTAGE_EBUILD_EXIT_FILE"
	if [[ -n $PORTAGE_IPC_DAEMON ]] ; then
		[[ ! -s $SANDBOX_LOG ]]
		"$PORTAGE_BIN_PATH"/ebuild-ipc exit $?
	fi
}
