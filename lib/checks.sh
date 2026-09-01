#!/usr/bin/env bash

function check_jce() {
    if "${1}"/bin/jrunscript -e 'exit (javax.crypto.Cipher.getMaxAllowedKeyLength("RC5") >= 256 ? 0 : 1);' > /dev/null 2>&1 ; then
            state "Java: JCE Files are installed for Oracle Java: ""${candidate}""/bin/java" 0
        else
            state "Java: JCE Files are not installed for Oracle Java: ""${candidate}""/bin/java" 1
        fi
}

function check_java() {
    # The following candidate list is from CM agent:
    # Starship/cmf/agents/cmf/service/common/cloudera-config.sh
    local JAVA17_HOME_CANDIDATES=(
      '/usr/java/jdk1.17'
      '/usr/lib/jvm/jdk-17'
      '/usr/lib/jvm/java-17-oracle'
    )
    local OPENJAVA17_HOME_CANDIDATES=(
      '/usr/lib/jvm/java-17'
      '/usr/lib/jvm/jdk-17'
      '/usr/lib/jvm/jdk1.17'
      '/usr/lib/jvm/zulu-17'
      '/usr/lib/jvm/zulu17'
      '/usr/lib64/jvm/java-17'
      '/usr/lib64/jvm/jdk1.17'
    )
    local JAVA11_HOME_CANDIDATES=(
      '/usr/java/jdk-11'
      '/usr/lib/jvm/jdk-11'
      '/usr/lib/jvm/java-11-oracle'
    )
    local OPENJAVA11_HOME_CANDIDATES=(
      '/usr/lib/jvm/java-11'
      '/usr/java/jdk-11'
      '/usr/lib/jvm/jdk-11'
      '/usr/lib64/jvm/jdk-11'
      '/usr/lib/jvm/zulu-11'
      '/usr/lib/jvm/zulu11'
      '/usr/lib/jvm/java-11-zulu-openjdk'
    )
    # JDK 6 and 7 candidate paths are intentionally gone: the supported JDK
    # floor for CDP Private Cloud Base 7.1.9 is JDK 8 (Support Matrix,
    # CDP 7.1.9 SP1: OpenJDK/OracleJDK/AzulJDK all list JDK 8 as the lowest
    # supported line; JDK 6/7 do not appear for any vendor).
    local JAVA8_HOME_CANDIDATES=(
      '/usr/java/jdk1.8'
      '/usr/java/jdk8'
      '/usr/java/jre1.8'
      '/usr/lib/jvm/j2sdk1.8-oracle'
      '/usr/lib/jvm/j2sdk1.8-oracle/jre'
      '/usr/lib/jvm/java-8-oracle'
    )
    local OPENJAVA8_HOME_CANDIDATES=(
      '/usr/lib/jvm/java-1.8.0-openjdk'
      '/usr/lib/jvm/java-8'
      '/usr/lib64/jvm/java-1.8.0-openjdk'
      '/usr/lib64/jvm/java-8-openjdk'
      '/usr/lib/jvm/zulu-8'
      '/usr/lib/jvm/zulu8'
      '/usr/lib/jvm/java-8-zulu-openjdk'
    )
    local MISCJAVA_HOME_CANDIDATES=(
      '/Library/Java/Home'
      '/usr/java/default'
      '/usr/lib/jvm/default-java'
      '/usr/lib/jvm/java-openjdk'
      '/usr/lib/jvm/jre-openjdk'
    )
    local JAVA_HOME_CANDIDATES=(
        "${JAVA17_HOME_CANDIDATES[@]}"
        "${JAVA11_HOME_CANDIDATES[@]}"
        "${JAVA8_HOME_CANDIDATES[@]}"
        "${MISCJAVA_HOME_CANDIDATES[@]}"
        "${OPENJAVA17_HOME_CANDIDATES[@]}"
        "${OPENJAVA11_HOME_CANDIDATES[@]}"
        "${OPENJAVA8_HOME_CANDIDATES[@]}"
    )

    function get_jdk_type() {
       java=$1
       JDK_TYPE=$($java -version 2>&1 | head -2 | tail -1 | awk '{print $1}')

       case $JDK_TYPE in
           Java\(TM\) )
               echo "Oracle";;
           OpenJDK )
               if [[ -z $($java -version 2>&1 | head -2 | tail -1 |grep Zulu) ]]; then
                   echo "OpenJDK"
               else
                   echo "Azul"
               fi
               ;;
           * )
               echo "Unknown";;
        esac
    }

    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-java-requirements.html
    # Supported JDK lines for CDP Private Cloud Base 7.1.9 (same for 7.1.9
    # SP1, Support Matrix): Oracle JDK 8/11/17, OpenJDK 8/11/17, Azul JDK
    # 8/11/17. JDK 21 is NOT supported for any vendor (Support Matrix,
    # CDP 7.1.9 SP1).
    # Minimum versions (cdpdc-java-requirements.html):
    #   JDK 8:  Oracle 1.8u181 (minimum required version)
    #           OpenJDK 1.8u232 (minimum required version; 1.8u231 is the
    #                            minimum for FIPS)
    #           Azul 8.56.0.21 (minimum required version)
    #   JDK 11: no general minimum version is documented. Tested/recommended
    #           builds listed by the doc: Oracle 11.0.10+8, OpenJDK
    #           11.0.4+11 (11.0.3 is the minimum for FIPS), Azul 11.50.19.
    #   JDK 17: no general minimum version is documented. Tested/recommended
    #           builds listed by the doc: Oracle 17.0.6, OpenJDK 17.0.7
    #           (17.0.2 is the minimum for FIPS), Azul 17.0.7.
    # TODO: task.md records an "Azul JDK 17 minimum build 11.50.19+" from the
    # Support Matrix, but 11.50.19 is the Azul JDK *11* build per the doc
    # above; the Azul JDK 17 tested build is 17.0.7. No authoritative Azul
    # JDK 17 minimum build could be confirmed — the check therefore applies
    # no Azul-specific JDK 17 floor, and this is flagged for manual
    # verification in the PR.
    java_found=false
    for candidate_regex in "${JAVA_HOME_CANDIDATES[@]}"; do
        # shellcheck disable=SC2045,SC2086
        for candidate in $(ls -rvd ${candidate_regex}* 2>/dev/null); do
            if [ -x "$candidate/bin/java" ]; then
                java_found=true
                JDK_VERSION=$($candidate/bin/java -version 2>&1 | head -1 | awk '{print $3}' | tr -d '"')
                # Legacy scheme up to JDK 8: "1.8.0_311" (also "1.7.0_80" etc.)
                # Modern scheme JDK 9+: "11.0.20", "17.0.9", "21.0.1".
                JDK_LEGACY_VERSION_REGEX='^1\.([0-9]+)\.'
                JDK_MODERN_VERSION_REGEX='^([0-9]+)\.([0-9]+)\.([0-9]+)'
                JDK_8_UPDATE_REGEX='^1\.8\.0_([0-9]+)'
                JDK_MODERN_VERSION_REGEX='^([0-9]+)\.([0-9]+)\.([0-9]+)'
                JDK_8_UPDATE_REGEX='^1\.8\.0_([0-9]+)'
                JDK_TYPE=$(get_jdk_type "$candidate/bin/java")
                support=true

                if [[ $JDK_VERSION =~ $JDK_LEGACY_VERSION_REGEX ]]; then
                    jdk_major=${BASH_REMATCH[1]}
                    if [[ $jdk_major -ne 8 ]]; then
                        # Only JDK 8 remains supported on the legacy 1.x
                        # scheme (Support Matrix, CDP 7.1.9 SP1).
                        support=false
                    elif [[ $JDK_TYPE == "Azul" ]]; then
                        # Azul JDK 1.8.0_XXX
                        # Azul JDK uses a different build versioning convention
                        AZUL_BUILD=$($candidate/bin/java -version 2>&1 | head -2 | tail -1 | awk '{print $5}' | cut -d'-' -f1)
                        AZUL_BUILD_REGEX='8\.([0-9]*)\.([0-9]*)\.([0-9]*)'
                        if [[ $AZUL_BUILD =~ $AZUL_BUILD_REGEX ]]; then
                            # Check if Azul build is lower than 8.56.0.21 which is the minimum required version
                            if [[ ${BASH_REMATCH[1]} -lt 56 ]]; then
                                support=false
                            elif [[ ${BASH_REMATCH[1]} -eq 56 ]] && [[ ${BASH_REMATCH[3]} -lt 21 ]]; then
                                support=false
                            else
                                support=true
                            fi
                        else
                            support=false
                        fi
                    else
                        # Oracle or OpenJDK 1.8.0_XXX
                        if [[ $JDK_VERSION =~ $JDK_8_UPDATE_REGEX ]]; then
                            if [[ $JDK_TYPE == "Oracle" ]] && [[ ${BASH_REMATCH[1]} -lt 181 ]]; then
                                support=false
                            elif [[ $JDK_TYPE == "OpenJDK" ]] && [[ ${BASH_REMATCH[1]} -lt 232 ]]; then
                                support=false
                            else
                                support=true
                            fi
                        else
                            support=false
                        fi
                    fi
                elif [[ $JDK_VERSION =~ $JDK_MODERN_VERSION_REGEX ]]; then
                    jdk_major=${BASH_REMATCH[1]}
                    case $jdk_major in
                        11)
                            # Oracle, OpenJDK and Azul Java 11 are all supported;
                            # no general minimum version is documented (see
                            # comment above for the tested/recommended builds).
                            if [[ $JDK_TYPE != "Unknown" ]]; then
                                support=true
                            else
                                support=false
                            fi
                            ;;
                        17)
                            # Oracle, OpenJDK and Azul Java 17 are all supported
                            # (Support Matrix, CDP 7.1.9 SP1). No general
                            # minimum version is documented (see comment above
                            # for the tested builds and the Azul TODO).
                            if [[ $JDK_TYPE != "Unknown" ]]; then
                                support=true
                            else
                                support=false
                            fi
                            ;;
                        21)
                            # JDK 21 is NOT supported for any vendor (Support
                            # Matrix, CDP 7.1.9 SP1).
                            support=false
                            ;;
                        *)
                            support=false
                            ;;
                    esac
                else
                    support=false
                fi

                if [[ $support == true ]]; then
                    state "Java: Supported $JDK_TYPE Java $JDK_VERSION: ${candidate}/bin/java" 0
                else
                    state "Java: Unsupported $JDK_TYPE Java $JDK_VERSION: ${candidate}/bin/java" 1
                fi
            fi
        done
    done
    if [ "$java_found" = false ] ; then
        state "Java: No JDK installed" 1
    fi
}

function check_os() (
    function check_rhel_version_support() {
        # Supported RHEL minor versions for CDP Private Cloud Base 7.1.9 SP1,
        # from the Cloudera Support Matrix (https://supportmatrix.cloudera.com/,
        # Products -> CDP Private Cloud Base -> 7.1.9 SP1 -> Operating Systems,
        # read 2026-09-01 as recorded in the task list; FIPS variants listed
        # where the matrix supports them):
        #   RHEL 7:  7.8, 7.9            (+ FIPS variants)
        #   RHEL 8:  8.2, 8.4, 8.6, 8.9, 8.10; 8.8 only in the 8.8 FIPS
        #            variant (plain 8.8 not listed); 8.7 not listed;
        #            8.10 FIPS supported
        #   RHEL 9:  9.1, 9.2, 9.5, 9.6, 9.7 (9.3 and 9.4 not listed; 9.6
        #            FIPS not listed)
        # TODO: the plain-8.8-unsupported-but-8.8-FIPS-supported split and the
        # 9.2 -> 9.5 (skipping 9.3/9.4) jump are unusual; re-verify in the
        # Support Matrix before relying on them (flagged in the PR).
        local rhel_version
        rhel_version=$(get_centos_rhel_version)
        if [ -z "$rhel_version" ]; then
            # Not CentOS/RHEL — the matrix here is RHEL-specific; other
            # distros are validated by their own entries and not by this
            # check.
            return 0
        fi

        local fips=unknown
        if command -v fips-mode-setup >/dev/null 2>&1; then
            # RHEL 8+: canonical FIPS state check
            if fips-mode-setup --check 2>/dev/null | grep -q "is enabled"; then
                fips=true
            else
                fips=false
            fi
        elif [ -r /proc/cmdline ] && grep -q "fips=1" /proc/cmdline; then
            # RHEL 7 fallback: fips-mode-setup is RHEL 8+ only
            fips=true
        fi

        local msg="System: RHEL $rhel_version support for CDP Private Cloud Base 7.1.9 SP1"
        case "$rhel_version" in
            7.8|7.9|8.2|8.4|8.6|8.9|8.10|9.1|9.2|9.5|9.6|9.7)
                state "$msg (FIPS: $fips)" 0
                ;;
            8.8)
                # Plain 8.8 is not in the matrix; 8.8 FIPS is.
                if [ "$fips" = true ]; then
                    state "$msg in FIPS mode" 0
                else
                    state "$msg: 8.8 is only supported in the FIPS variant (Support Matrix, CDP 7.1.9 SP1). Actual FIPS state: $fips" 1
                fi
                ;;
            *)
                state "$msg: this RHEL minor version is not in the Support Matrix (FIPS: $fips). See https://supportmatrix.cloudera.com/" 1
                ;;
        esac
    }

    function check_swappiness() {
        # http://www.cloudera.com/content/www/en-us/documentation/enterprise/latest/topics/cdh_admin_performance.html#xd_583c10bfdbd326ba-7dae4aa6-147c30d0933--7fd5__section_xpq_sdf_jq
        local swappiness
        local msg="System: /proc/sys/vm/swappiness should be 1"
        swappiness=$(cat /proc/sys/vm/swappiness)
        if [ "$swappiness" -eq 1 ]; then
            state "$msg" 0
        else
            state "$msg. Actual: $swappiness" 1
        fi
    }

    function check_swappiness_persist() {
        # Same source as check_swappiness. The runtime /proc value above
        # does not survive a reboot unless persisted via sysctl (same
        # silent-revert risk that check_thp_grub already guards against for
        # THP) — check for a persisted vm.swappiness=1 in /etc/sysctl.conf
        # or /etc/sysctl.d/*.conf.
        local msg="System: vm.swappiness=1 should be persisted in /etc/sysctl.conf or /etc/sysctl.d/*.conf"
        local -a sysctl_files=()
        [ -f /etc/sysctl.conf ] && sysctl_files+=(/etc/sysctl.conf)
        local f
        for f in /etc/sysctl.d/*.conf; do
            [ -f "$f" ] && sysctl_files+=("$f")
        done
        if [ ${#sysctl_files[@]} -gt 0 ] && \
           grep -Eq '^[[:space:]]*vm\.swappiness[[:space:]]*=[[:space:]]*1[[:space:]]*$' "${sysctl_files[@]}"; then
            state "$msg" 0
        else
            state "$msg. Not found — setting will silently revert on reboot" 1
        fi
    }

    function check_overcommit_memory() {
        # https://www.cloudera.com/documentation/enterprise/5-15-x/topics/impala_scalability.html#kerberos_overhead_memory_usage
        local overcommit_memory
        local msg="System: /proc/sys/vm/overcommit_memory should be 1"
        overcommit_memory=$(cat /proc/sys/vm/overcommit_memory)
        if [ "$overcommit_memory" -eq 1 ]; then
            state "$msg" 0
        else
            state "$msg. Actual: $overcommit_memory" 1
        fi
    }

    function check_overcommit_memory_persist() {
        # Same source as check_overcommit_memory; same persistence risk as
        # check_swappiness_persist above.
        local msg="System: vm.overcommit_memory=1 should be persisted in /etc/sysctl.conf or /etc/sysctl.d/*.conf"
        local -a sysctl_files=()
        [ -f /etc/sysctl.conf ] && sysctl_files+=(/etc/sysctl.conf)
        local f
        for f in /etc/sysctl.d/*.conf; do
            [ -f "$f" ] && sysctl_files+=("$f")
        done
        if [ ${#sysctl_files[@]} -gt 0 ] && \
           grep -Eq '^[[:space:]]*vm\.overcommit_memory[[:space:]]*=[[:space:]]*1[[:space:]]*$' "${sysctl_files[@]}"; then
            state "$msg" 0
        else
            state "$msg. Not found — setting will silently revert on reboot" 1
        fi
    }

    function check_tuned() {
        # "tuned" service should be disabled on RHEL/CentOS hosts: an active
        # tuned profile can silently re-enable transparent hugepages (which
        # must stay disabled,
        # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/managing-clusters/topics/cm-disabling-transparent-hugepages.html
        # for "RHEL/CentOS 7.x, 8.x, and 9.x") after the THP settings have
        # been applied.
        # The disable-tuned instruction itself is documented for RHEL/CentOS
        # 7.x only: "If your cluster hosts are running RHEL/CentOS 7.x,
        # disable the "tuned" service" (Cloudera Enterprise "Optimizing
        # Performance in CDH",
        # https://docs.cloudera.com/documentation/enterprise/latest/topics/cdh_admin_performance.html
        # — page no longer online; archived copy via web.archive.org,
        # snapshot 2024-03-02). The CDP 7.1.9 documentation book has no
        # tuned guidance at all, so on RHEL 8/9 a running tuned daemon is a
        # warning (THP re-enable risk) rather than a hard failure.
        local rhel_major
        rhel_major=$(get_centos_rhel_major_version)
        # tuned check is systemd-based and Cloudera-documented for RHEL 7+;
        # silently skip anything else (mirrors the old RHEL7-only gate).
        if [ -z "$rhel_major" ] || [ "$rhel_major" -lt 7 ]; then
            return 0
        fi
        local fail_flag=1
        if [ "$rhel_major" -ge 8 ]; then
            fail_flag=2
        fi
        systemctl status tuned &>/dev/null
        case $? in
            0) state "System: tuned is running" $fail_flag;;
            3) state "System: tuned is not running" 0;;
            *) state "System: tuned is not installed" 0;;
        esac
        if [ "$(systemctl is-enabled tuned 2>/dev/null)" == "enabled" ]; then
            state "System: tuned auto-starts on boot" $fail_flag
        else
            state "System: tuned does not auto-start on boot" 0
        fi
    }

    function check_thp_defrag() {
        # Older RHEL/CentOS versions use [1], while newer versions (e.g. 7.1) and
        # Ubuntu/Debian use [2]:
        #   1: /sys/kernel/mm/redhat_transparent_hugepage/defrag
        #   2: /sys/kernel/mm/transparent_hugepage/defrag.
        # http://www.cloudera.com/content/www/en-us/documentation/enterprise/latest/topics/cdh_admin_performance.html#cdh_performance__section_hw3_sdf_jq
        local file
        file=$(find /sys/kernel/mm/ -type d -name '*transparent_hugepage')/defrag
        if [ -f "$file" ]; then
            local msg="System: $file should be disabled"
            if grep -F -q "[never]" "$file"; then
                state "$msg" 0
            else
                state "$msg. Actual: $(awk '{print $1}' "$file" | sed -e 's/\[//' -e 's/\]//')" 1
            fi
        else
            state "System: /sys/kernel/mm/*transparent_hugepage not found. Check skipped" 2
        fi
    }

    function check_thp_enabled() {
        # https://docs.cloudera.com/documentation/enterprise/latest/topics/cdh_admin_performance.html#cdh_performance__section_hw3_sdf_jq
        local file
        file=$(find /sys/kernel/mm/ -type d -name '*transparent_hugepage')/enabled
        if [ -f "$file" ]; then
            local msg="System: $file should be disabled"
            if grep -F -q "[never]" "$file"; then
                state "$msg" 0
            else
                state "$msg. Actual: $(awk '{print $1}' "$file" | sed -e 's/\[//' -e 's/\]//')" 1
            fi
        else
            state "System: /sys/kernel/mm/*transparent_hugepage not found. Check skipped" 2
        fi
    }

    function check_thp_grub() {
        # If your cluster hosts are running RHEL/CentOS 7.x, modify the GRUB configuration to disable THP
        # https://docs.cloudera.com/documentation/enterprise/latest/topics/cdh_admin_performance.html#cdh_performance__section_hw3_sdf_jq
        if [ -f "/etc/default/grub" ]; then
            local msg="System: /etc/default/grub should have 'transparent_hugepage=never' appended to GRUB_CMDLINE_LINUX"
            if grep -F -q "transparent_hugepage=never" "/etc/default/grub"; then
                state "$msg" 0
            else
                state "$msg. Actual: $(grep GRUB_CMDLINE_LINUX /etc/default/grub)" 1
            fi
        else
            state "System: /etc/default/grub not found. Check skipped" 2
        fi
    }

    function check_selinux() {
        # http://www.cloudera.com/content/www/en-us/documentation/enterprise/latest/topics/install_cdh_disable_selinux.html
        local msg="System: SELinux should be disabled"
        case $(getenforce) in
            Disabled|Permissive) state "$msg" 0;;
            *)                   state "$msg. Actual: $(getenforce)" 1;;
        esac
    }

    # Check that the system clock is synced by either ntpd or chronyd.
    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-enable-NTP-service.html
    # "Runtime requires that you configure a Network Time Protocol (NTP)
    # service on each machine in your cluster." — the doc accepts either
    # daemon ("Most operating systems include the ntpd service", "Some
    # operating systems use chronyd by default") and warns that running both
    # at once makes Cloudera Manager report clock offset errors even when
    # time is correct.
    # The old "kudu supports only ntpd" warning is obsolete: upstream Kudu
    # requirements list "ntp or chrony"
    # (https://kudu.apache.org/docs/installation.html, "Operating System
    # Requirements"), and chronyd is the default NTP daemon on RHEL 8/9.
    function check_time_sync() (
        function is_ntp_in_sync() {
            if [ "$(ntpstat 2>/dev/null | grep -c "synchronised to NTP server")" -eq 1 ]; then
                state "System: ntpd clock synced" 0
            else
                state "System: ntpd clock NOT synced. Check 'ntpstat'" 1
            fi
        }

        function is_chrony_in_sync() {
            if chronyc tracking 2>/dev/null | grep -q "Leap status     : Normal"; then
                state "System: chronyd clock synced" 0
            else
                state "System: chronyd clock NOT synced. Check 'chronyc tracking'" 1
            fi
        }

        if [ -n "$(get_centos_rhel_major_version)" ]; then
            # ntpd and chronyd are both acceptable on RHEL/CentOS 7/8/9, but
            # only one of them should run at a time.
            get_service_state 'ntpd'
            local ntpd_running=${SERVICE_STATE['running']}
            get_service_state 'chronyd'
            local chronyd_running=${SERVICE_STATE['running']}

            if $ntpd_running && $chronyd_running; then
                state "System: Both ntpd and chronyd are running. Only one NTP daemon should run; running both makes Cloudera Manager report clock offset errors. Disable one of them." 1
            elif $ntpd_running; then
                _check_service_is_running 'System' 'ntpd'
                is_ntp_in_sync
            elif $chronyd_running; then
                _check_service_is_running 'System' 'chronyd'
                is_chrony_in_sync
            else
                state "System: Neither ntpd nor chronyd is running. An NTP service must run on every cluster host." 1
            fi
        else
            _check_service_is_running 'System' 'ntpd'
        fi
    )

    function check_32bit_packages() {
        local packages_32bit
        packages_32bit=$(rpm -qa --queryformat '\t%{NAME} %{ARCH}\n' | grep 'i[6543]86' | cut -d' ' -f1)
        if [ "$packages_32bit" ]; then
            state "System: Found the following 32bit packages installed:\n$packages_32bit" 2
        else
            state "System: Only 64bit packages should be installed" 0
        fi
    }

    function check_unneeded_services() {
        local UNNECESSARY_SERVICES=(
            'bluetooth'
            'cups'
            'ip6tables'
            'postfix'
        )
        for service_name in "${UNNECESSARY_SERVICES[@]}"; do
            _check_service_is_not_running 'System' "$service_name" 2
        done
    }

    function check_tmp_noexec() {
        local noexec=false
        for option in $(findmnt -lno options --target /tmp | tr ',' ' '); do
            if [[ "$option" = 'noexec' ]]; then
                noexec=true
            fi
        done
        if $noexec; then
            state "System: /tmp mounted with noexec fails for CM versions older than 5.8.4, 5.9.2, and 5.10.0" 2
        else
            state "System: /tmp mounted with noexec fails for CM versions older than 5.8.4, 5.9.2, and 5.10.0" 0
        fi
    }
    function check_entropy() {
        local entropy
        entropy=$(cat /proc/sys/kernel/random/entropy_avail)
        if [ "$entropy" -gt 500 ]; then
            state "System: Entropy is $entropy" 0
        else
            state "System: Entropy should be more than 500, Actual: $entropy -- Please see https://bit.ly/2IoOj0K" 2
        fi
    }
    check_rhel_version_support
    check_swappiness
    check_swappiness_persist
    check_overcommit_memory
    check_overcommit_memory_persist
    check_tuned
    check_thp_defrag
    check_thp_enabled
    check_thp_grub
    check_selinux
    check_time_sync
    check_32bit_packages
    check_unneeded_services
    check_tmp_noexec
    check_entropy
)

function check_database() {
    # Supported database versions for CDP Private Cloud Base 7.1.9 SP1
    # (Cloudera Support Matrix, https://supportmatrix.cloudera.com/,
    # CDP Private Cloud Base -> 7.1.9 SP1 -> Databases, read 2026-09-01):
    #   MySQL:    8.4, 8.0, 5.7         (5.6 supported on base 7.1.9 but NOT on SP1)
    #   MariaDB:  10.11, 10.6, 10.5, 10.4 (10.3 and 10.2 NOT supported on SP1)
    #   PostgreSQL: 17, 16, 15, 14, 13, 12 (11 and 10 NOT supported on SP1)
    #   OracleDB: 23c, 21c, 19c, 19, RAC 19
    # Notes:
    # - These are the versions supported as the Cloudera Manager / cluster
    #   backend. Only a server installed locally (same host as Cloudera
    #   Manager) can be detected here; a backend on a remote host is not
    #   visible to this check.
    # - OracleDB is not RPM-detectable on cluster hosts (an Oracle backend
    #   normally runs on its own server); the JDBC/connector check and the
    #   Cloudera Manager install wizard cover it, so this check skips it.

    # Report on a single server RPM. $1: engine label, $2: rpm name,
    # $3: supported-version list (comma-separated, no spaces), $4: rpm
    # version string, $5: "major" to compare only the major version
    # (PostgreSQL) or "major.minor" (default; MySQL/MariaDB).
    function report_db_version() {
        local engine="$1"
        local rpm_name="$2"
        local supported_list="$3"
        local rpm_version="$4"
        local version_mode="${5:-major.minor}"
        local ver
        if [[ $version_mode == major ]]; then
            [[ $rpm_version =~ ([0-9]+) ]] || return 1
            ver=${BASH_REMATCH[1]}
        else
            # RPM VERSION fields are usually X.Y.Z, but module/Software-
            # Collection builds can carry X.Y only — compare major.minor.
            [[ $rpm_version =~ ([0-9]+)\.([0-9]+) ]] || return 1
            ver="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        fi
        local rpm_full
        rpm_full=$(rpm -q "$rpm_name")
        # NB: a case pattern cannot be built from a variable (the "|"
        # alternation is parsed, not expanded), so match by containment
        # against the comma-delimited list instead.
        if [[ ",$supported_list," == *",$ver,"* ]]; then
            state "Database: Supported $engine server installed ($ver). $rpm_full" 0
        else
            state "Database: Unsupported $engine server installed ($ver). $rpm_full (supported on CDP 7.1.9 SP1: $(echo "$supported_list" | tr ',' ' '))" 1
        fi
        return 0
    }

    local found_any=false
    local rpm_version

    for rpm_name in mysql-commercial-server mysql-community-server; do
        rpm_version=$(rpm -q --queryformat='%{VERSION}' "$rpm_name" 2>/dev/null)
        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]] && report_db_version 'MySQL' "$rpm_name" '8.4,8.0,5.7' "$rpm_version"; then
            found_any=true
        fi
    done

    rpm_version=$(rpm -q --queryformat='%{VERSION}' mariadb-server 2>/dev/null)
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]] && report_db_version 'MariaDB' 'mariadb-server' '10.11,10.6,10.5,10.4' "$rpm_version"; then
        found_any=true
    fi

    # PostgreSQL server RPM naming varies by repo: "postgresql-server"
    # (RHEL app-stream), "postgresqlNN-server" (PGDG), or
    # "rh-postgresqlNN-postgresql-server" (Software Collections). Querying
    # this bounded candidate list directly is more reliable than parsing
    # names back out of "rpm -qa" output (which embeds version-release).
    local pg_rpm_name
    # shellcheck disable=SC2013
    for pg_rpm_name in postgresql-server \
                       postgresql12-server postgresql13-server postgresql14-server \
                       postgresql15-server postgresql16-server postgresql17-server \
                       rh-postgresql12-postgresql-server rh-postgresql13-postgresql-server \
                       rh-postgresql14-postgresql-server rh-postgresql15-postgresql-server; do
        rpm_version=$(rpm -q --queryformat='%{VERSION}' "$pg_rpm_name" 2>/dev/null)
        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]] && report_db_version 'PostgreSQL' "$pg_rpm_name" '17,16,15,14,13,12' "$rpm_version" 'major'; then
            found_any=true
        fi
    done

    if [[ $found_any == false ]]; then
        state "Database: No database server RPM installed locally, skipping version check (remote backends are not detected here)" 2
    fi
}

function check_jdbc_connector() {
    # See Installing the MySQL JDBC Driver
    # https://www.cloudera.com/documentation/enterprise/latest/topics/cm_ig_mysql.html#cmig_topic_5_5_3
    local connector=/usr/share/java/mysql-connector-java.jar
    if [ -f $connector ]; then
        state "Database: MySQL JDBC Driver is installed" 0
    else
        state "Database: MySQL JDBC Driver is not installed" 2
    fi
}

function check_python() {
    # Supported Python versions for CDP Private Cloud Base 7.1.9 SP1
    # (Cloudera Support Matrix, https://supportmatrix.cloudera.com/,
    # CDP Private Cloud Base -> 7.1.9 SP1, read 2026-09-01):
    #   3.11, 3.10, 3.9, 3.8, 3.7, 3.6, 2.7
    # Per-OS floors and patch minimums, from
    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-cm-install-python-3.8.html
    # ("Installing Python 3" — "You must install Python 3.8.12 or higher on
    # all cluster hosts before installing Cloudera Manager", "The minimum
    # required version of Python 3.8 is 3.8.12. The minimum version of
    # Python 3.9 is 3.9.14." and the per-OS table: RHEL 8.x requires
    # Python 3.8, RHEL 9.x requires Python 3.9, RHEL 7 must build 3.8
    # from source):
    #   RHEL 7: Python 3.8 (3.8.12+), not in RHEL7 repos — source build
    #   RHEL 8: Python 3.8 (3.8.12+)
    #   RHEL 9: Python 3.9 (3.9.14+)
    local rhel_major
    rhel_major=$(get_centos_rhel_major_version)

    # Display form and numeric floor for this OS. The patch-level floor
    # applies only to the required minor line: a newer minor (e.g. 3.11 on
    # RHEL 8) is fine per the Support Matrix regardless of its patch number.
    local required_version="3.8.12"
    local required_minor=8
    local required_patch=12
    case "$rhel_major" in
        7) required_version="3.8.12 (Python 3.8; must be built from source on RHEL 7)" ;;
        8) required_version="3.8.12"; required_minor=8; required_patch=12 ;;
        9) required_version="3.9.14"; required_minor=9; required_patch=14 ;;
        *) required_version="3.8.12 or 3.9.14 depending on OS (see doc)"; required_minor=8; required_patch=12 ;;
    esac

    # The interpreter CM agents will actually invoke. This script is run as
    # root on target hosts, so "command -v python3" resolves the same way the
    # CM agent sees it (not a user-level venv/pyenv shim).
    local python3_bin
    python3_bin=$(command -v python3 2>/dev/null)
    if [ -z "$python3_bin" ]; then
        state "Python: python3 not found on PATH. CDP requires Python 3 (minimum $required_version). Install python3 via the OS package manager (e.g. dnf install python3) or from source." 1
        return 1
    fi

    # Older Python 3 builds print the version to stderr, so capture both.
    local active_version
    active_version=$("$python3_bin" --version 2>&1 | awk '{print $2}')

    # Enumerate all python3.x interpreters on the host, not just the one
    # first on PATH: RHEL hosts can have multiple (e.g. python3.6 from the OS
    # plus python39/python3.11 module streams) and Cloudera Manager picks
    # the interpreter per host configuration. Sources:
    #  - "alternatives" symlinks (RHEL's update-alternatives registry)
    #  - /usr/bin/python3.* and /usr/local/bin/python3.* convention
    local -a found=()
    local -a versions=()
    local -a scan_paths=()
    local p
    # alternatives --list format: "name auto priority path" (RHEL 8/9) or
    # tab-separated columns on RHEL 7; just take the path column and filter
    # for python3 executables.
    while read -r p; do
        [ -n "$p" ] && scan_paths+=("$p")
    done <<< "$(alternatives --list 2>/dev/null | awk '$1 ~ /^python3/ {print $NF}')"
    # shellcheck disable=SC2045
    for p in $(ls -d /usr/bin/python3.* /usr/local/bin/python3.* 2>/dev/null); do
        if [ -x "$p" ] && [ ! -L "$p" ]; then
            scan_paths+=("$p")
        fi
    done
    # Keep real executables, deduplicated (the python3.6 "binaries" under
    # /usr/bin can be symlinks; the version probe skips anything that does
    # not report a version).
    local seen=''
    local v
    for p in "${scan_paths[@]}"; do
        [ -x "$p" ] || continue
        case "$seen" in *"|$p|"*) continue ;; esac
        seen="|$p|${seen}"
        v=$("$p" --version 2>&1 | awk '{print $2}')
        [ -z "$v" ] && continue
        found+=("$p")
        versions+=("$v")
    done

    # Report every detected interpreter with its path.
    local i
    for i in "${!versions[@]}"; do
        state "Python: ${found[$i]} -> ${versions[$i]}" 0
    done

    # Validate the active PATH-resolved interpreter against the doc floor for
    # this OS. Version string form: "3.8.12", "3.9.14", "3.11.4", or even
    # "3.8" (patch omitted). A version on a NEWER minor than the required
    # line passes regardless of patch number (Support Matrix supports
    # 3.9-3.11 on SP1); the patch floor only bites on the required minor
    # itself (e.g. 3.8.x < 3.8.12 on RHEL 8).
    local active_minor active_patch
    active_minor=$(echo "$active_version" | cut -d. -f2)
    active_patch=$(echo "$active_version" | cut -d. -f3)
    local unsupported_reason=""
    if [ -z "$active_minor" ]; then
        unsupported_reason="could not parse version from '$python3_bin --version' (got '$active_version')"
    elif [ "$active_minor" -lt "$required_minor" ]; then
        unsupported_reason="Python $active_version is below the required Python 3.$required_minor ($required_version) for this OS"
    elif [ "$active_minor" -eq "$required_minor" ] && [ -n "$active_patch" ] && [ "$active_patch" -lt "$required_patch" ]; then
        unsupported_reason="Python $active_version is below the minimum patch level ($required_version)"
    fi

    if [ -n "$unsupported_reason" ]; then
        state "Python: $python3_bin is $active_version — $unsupported_reason. See https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-cm-install-python-3.8.html" 1
        return 1
    fi

    # Active interpreter meets the floor. If other python3.x interpreters
    # exist that are below the floor, warn: CM agent configuration may point
    # at any of them.
    for i in "${!versions[@]}"; do
        local v_minor v_patch
        v_minor=$(echo "${versions[$i]}" | cut -d. -f2)
        v_patch=$(echo "${versions[$i]}" | cut -d. -f3)
        if [ -n "$v_minor" ] && { [ "$v_minor" -lt "$required_minor" ] || { [ "$v_minor" -eq "$required_minor" ] && [ -n "$v_patch" ] && [ "$v_patch" -lt "$required_patch" ]; }; }; then
            state "Python: additional interpreter ${found[$i]} is ${versions[$i]}, below the $required_version floor — fine unless CM is configured to use it" 2
        fi
    done

    state "Python: Active python3 is $active_version at $python3_bin; required minimum for RHEL $rhel_major is $required_version" 0
}

function check_network() (

    function check_hostname() {
        local fqdn
        local short
        fqdn=$(hostname -f)
        short=$(hostname -s)

        # https://en.wikipedia.org/wiki/Hostname
        # Hostnames are composed of series of labels concatenated with dots, as are
        # all domain names. Each label must be from 1 to 63 characters long, and the
        # entire hostname (including delimiting dots but not a trailing dot) has a
        # maximum of 253 ASCII characters.
        local VALID_FQDN='^([a-z]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9\-]{0,61}[a-z0-9])?$'
        echo "$fqdn" | grep -Eiq "$VALID_FQDN"
        local valid_format=$?
        if [[ $valid_format -eq 0 && ${#fqdn} -le 253 ]]; then
            if [[ ${#short} -gt 15 ]]; then
                # Microsoft still recommends computer names less than or equal to 15 characters.
                # https://serverfault.com/questions/123343/is-the-netbios-limt-of-15-charactors-still-a-factor-when-naming-computers
                # https://technet.microsoft.com/en-us/library/cc731383.aspx
                # If hostname is longer than that, we cannot do SSSD or Centrify etc to
                # add the node to domain. Won't work well with Kerberos/AD.
                state "Network: Computer name should be <= 15 characters (NetBIOS restriction)" 1
            else
                if [[ "${fqdn//\.*/}" = "$short" ]]; then
                    if [[ $(echo "$fqdn" | grep '[A-Z]') = "" ]]; then
                        state "Network: Hostname looks good (FQDN, no uppercase letters)" 0
                    else
                        # Cluster hosts must have a working network name resolution system and
                        # correctly formatted /etc/hosts file. All cluster hosts must have properly
                        # configured forward and reverse host resolution through DNS.
                        # The /etc/hosts files must:
                        # - Not contain uppercase hostnames
                        # https://www.cloudera.com/documentation/enterprise/release-notes/topics/rn_consolidated_pcm.html#cm_cdh_compatibility
                        state "Network: Hostname should not contain uppercase letters" 1
                    fi
                else
                    state "Network: Hostname misconfiguration (shortname and host label of FQDN don't match)" 2
                fi
            fi
        else
            # Important
            # - The canonical name of each host in /etc/hosts `must' be the FQDN
            # - Do not use aliases, either in /etc/hosts or in configuring DNS
            # https://www.cloudera.com/documentation/enterprise/latest/topics/cdh_ig_networknames_configure.html
            state "Network: Malformed hostname is configured (consult RFC)" 1
        fi
    }

    # Networking Protocols Support
    # CDH requires IPv4. IPv6 is not supported and must be disabled.
    # https://www.cloudera.com/documentation/enterprise/release-notes/topics/rn_consolidated_pcm.html
    function check_ipv6() {
        local msg="Network: IPv6 is not supported and must be disabled"
        if ip addr show | grep -q inet6; then
            state "${msg}" 1
        else
            state "${msg}" 0
        fi
    }

    function check_etc_hosts() {
        local entries
        entries=$(grep -cEv "^#|^ *$" /etc/hosts)
        local msg="Network: /etc/hosts entries should be <= 2 (use DNS). Actual: $entries"
        if [ "$entries" -le 2 ]; then
            local rc=0
            while read -r line; do
                entry=$(echo "$line" | grep -Ev "^#|^ *$")
                if [ ! "$entry" = "" ]; then
                    # the following line ('set -- $(...)') can't be quoted
                    # shellcheck disable=SC2046
                    set -- $(echo "$line" | awk '{ print $1, $2 }')
                    if [ "$1" = "127.0.0.1" ] || [ "$1" = "::1" ] && [ "$2" = "localhost" ]; then
                        :
                    else
                        rc=1
                    fi
                fi
            done < /etc/hosts
            if [ "$rc" -eq 0 ]; then
                state "$msg" 0
            else
                state "${msg}, but has non localhost" 2
            fi
        else
            state "$msg" 2
        fi
    }

    function check_nscd_and_sssd() {
        _check_service_is_running 'Network' 'sssd' 2
        local sssd_running=${SERVICE_STATE['running']}

        # nscd's own installed/running/autostart state is informational
        # only: whether it should be running isn't a fixed CDP
        # requirement, it depends on whether sssd is in use. Report every
        # branch at the same informational level directly (rather than
        # via _check_service_is_running, which hardcodes "running" as
        # PASS regardless of the msgflag passed in).
        get_service_state 'nscd'
        local nscd_installed=${SERVICE_STATE['installed']}
        local nscd_running=${SERVICE_STATE['running']}
        local nscd_autostart=${SERVICE_STATE['autostart']}
        if [ "$nscd_installed" = true ]; then
            if [ "$nscd_running" = true ]; then
                state "Network: nscd is running" 2
            else
                state "Network: nscd is not running" 2
            fi
            if [ "$nscd_autostart" = true ]; then
                state "Network: nscd auto-starts on boot" 2
            else
                state "Network: nscd does not auto-start on boot" 2
            fi
        else
            state "Network: nscd is not installed" 2
        fi

        # Preferred configuration when sssd is active: nscd disabled, or
        # not installed at all (SSSD is the preferred name service cache;
        # nscd isn't designed to run alongside it).
        # https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System-Level_Authentication_Guide/usingnscd-sssd.html
        if $sssd_running; then
            if [ "$nscd_running" = true ]; then
                state "Network: sssd is active — nscd should be disabled or uninstalled, not run alongside it (sssd is the preferred name service cache)" 2
            elif [ "$nscd_installed" = true ]; then
                state "Network: sssd is active and nscd is installed but disabled (preferred; uninstalling nscd entirely is also fine)" 0
            else
                state "Network: sssd is active and nscd is not installed (preferred)" 0
            fi
        fi

        if [ "$nscd_running" = true ] && $sssd_running; then
            # 7.8. USING NSCD WITH SSSD
            # SSSD is not designed to be used with the NSCD daemon.
            # Even though SSSD does not directly conflict with NSCD, using both services
            # can result in unexpected behavior, especially with how long entries are cached.
            # https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System-Level_Authentication_Guide/usingnscd-sssd.html

            # How-to: Deploy Apache Hadoop Clusters Like a Boss
            # Name Service Caching
            # If you’re running Red Hat SSSD, you’ll need to modify the nscd configuration;
            # with SSSD enabled, don’t use nscd to cache passwd, group, or netgroup information.
            # http://blog.cloudera.com/blog/2015/01/how-to-deploy-apache-hadoop-clusters-like-a-boss/
            # shellcheck disable=SC2013
            for cached in $(awk '/^[^#]*enable-cache.*yes/ { print $2 }' /etc/nscd.conf); do
                case $cached in
                    'passwd'|'group'|'netgroup')
                        state "Network: nscd should not cache $cached with sssd enabled" 1
                        ;;
                    *)
                        ;;
                esac
            done
            # shellcheck disable=SC2013
            for non_cached in $(awk '/^[^#]*enable-cache.*no/ { print $2 }' /etc/nscd.conf); do
                case $non_cached in
                    'passwd'|'group'|'netgroup')
                        state "Network: nscd shoud not cache $non_cached with sssd enabled" 0
                        ;;
                    *)
                        ;;
                esac
            done
        fi
    }

    # Consistency check on forward (hostname to ip address) and
    # reverse (ip address to hostname) resolutions.
    # Note that an additional `.' in the PTR ANSWER SECTION.
    function check_dns() {
        if ! command -v dig 2&>/dev/null ; then
            state "Network: 'dig' not found, skipping DNS checks. Run 'sudo yum install bind-utils' to fix." 2
            return
        fi

        local fqdn
        local fwd_lookup
        local rvs_lookup
        fqdn=$(hostname -f)
        fwd_lookup=$(dig -4 "$fqdn" A +short)
        rvs_lookup=$(dig -4 -x "$fwd_lookup" PTR +short)
        if [[ "${fqdn}." = "$rvs_lookup" ]]; then
            state "Network: Consistent name resolution of $fqdn" 0
        else
            state "Network: Inconsistent name resolution of $fqdn. Check DNS configuration" 1
        fi
    }
    check_ipv6
    check_hostname
    check_etc_hosts
    check_nscd_and_sssd
    check_dns
)

function check_firewall() {
    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-disabling-firewall.html
    # "To disable the firewall on each host in your cluster, perform the
    # following steps on each host." The RHEL-labelled step is
    # "sudo systemctl disable firewalld" / "sudo systemctl stop firewalld"
    # (labeled "RHEL 7 compatible" in the doc). The doc has no RHEL8/9-specific
    # variant, but firewalld is the default firewall service on RHEL 8 and 9
    # as well (the iptables service is not shipped as a systemd unit by
    # default on RHEL 8/9), so the same firewalld check applies to 7/8/9.
    # Non-RHEL/CentOS systems (older CentOS 6 etc.) keep the legacy iptables
    # check.
    if [ -n "$(get_centos_rhel_major_version)" ]; then
        _check_service_is_not_running 'Network' 'firewalld'
    else
        _check_service_is_not_running 'Network' 'iptables'
    fi
}

function check_fapolicyd() {
    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-before-you-install.html
    # Caution note (verbatim): "Cloudera requires disabling the fapolicyd
    # daemon present in RHEL 8 (and later) systems before beginning
    # installation" of the Cloudera Manager application. "Improper
    # configuration may render the system non-functional."
    # fapolicyd does not exist on RHEL 7 and earlier, so this check is
    # RHEL 8+ only.
    local rhel_major
    rhel_major=$(get_centos_rhel_major_version)
    if [ -z "$rhel_major" ] || [ "$rhel_major" -lt 8 ]; then
        return 0
    fi
    _check_service_is_not_running 'System' 'fapolicyd'
}

function check_sudo() {
    # https://docs.cloudera.com/cdp-private-cloud-base/7.1.9/installation/topics/cdpdc-installation-wizard.html
    # "Enter the root name or username for the root account that has
    # password-less sudo privileges." Sudoers entry format given there:
    # "%<username> ALL=(ALL) NOPASSWD: ALL". CM Server needs this (or the
    # root account) to log into each host over SSH during install.
    local msg="System: current user must be root or have password-less sudo (required for CM Server host login)"
    if [ "$(id -u)" -eq 0 ]; then
        state "$msg. Running as root" 0
    elif sudo -n true 2>/dev/null; then
        state "$msg. Password-less sudo confirmed" 0
    else
        state "$msg. sudo requires a password or is not permitted for this user" 1
    fi
}

function check_opt_cloudera_disk_space() {
    # /opt/cloudera should have at least 100 GB available: "100 GB for CM"
    # and "100 GB for all hosts" as the minimum space needed for each
    # installed and retained CDP version. Not stated in the CDP 7.1.9
    # Private Cloud Base install book itself; sourced from the CDP
    # upgrade guide's disk-space/mountpoint requirements table (same
    # /opt/cloudera requirement, different book — no 7.1.9-base-book page
    # was found stating this number independently):
    # https://docs-archive.cloudera.com/cdp-private-cloud-upgrade/latest/upgrade-hdp3/topics/amb3-diskspace-mountpoint.html
    local required_gb=100
    local check_path="/opt/cloudera"
    # /opt/cloudera won't exist yet on a host being prereq-checked before
    # install — fall back to whichever ancestor directory actually exists,
    # since that's the mountpoint /opt/cloudera will land on once created.
    if [ ! -d "$check_path" ]; then
        check_path="/opt"
    fi
    if [ ! -d "$check_path" ]; then
        check_path="/"
    fi
    local avail_kb
    avail_kb=$(df -Pk "$check_path" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$avail_kb" ]; then
        state "System: could not determine available disk space for $check_path. Check skipped" 2
        return 0
    fi
    local avail_gb=$((avail_kb / 1024 / 1024))
    local msg="System: $check_path should have at least ${required_gb}GB available (100 GB per installed/retained CDP version). Actual: ${avail_gb}GB"
    if [ "$avail_gb" -ge "$required_gb" ]; then
        state "$msg" 0
    else
        state "$msg" 2
    fi
}

function check_data_disk_mounts() {
    # HDFS/DataNode data-disk filesystem & mount guidance, Cloudera
    # Reference Architecture "Filesystems":
    # https://docs.cloudera.com/cdp-reference-architectures/latest/cdp-pvc-base-ra/topics/ra-cdpdc-filesystems.html
    # - "Cloudera recommends using an extent-based filesystem. This
    #   includes ext3, ext4, and xfs."
    # - ext4: reduce the superuser block reservation from the 5% default
    #   to 1% ("-m1" at mkfs time).
    # - "Drives should be mounted in the /etc/fstab filesystem table
    #   using the noatime option."
    #
    # This guidance is sourced from HDFS/DataNode docs specifically, but
    # is applied here to every additional local data-disk mount found on
    # the host, not just ones named /data* (that was the old
    # print_disks()/data_mounts() behaviour, informational-only and
    # pattern-matched on the mountpoint containing "/data" — real
    # deployments name data disks many ways: /data1..N, /kafka1..N,
    # /nifi-content, /grid/0..N, etc., so name-matching silently misses
    # most of them). At prereq-check time it isn't yet known which mount
    # will end up assigned to HDFS vs YARN vs another workload anyway —
    # and YARN nodemanager local dirs are typically colocated on the same
    # physical disks as HDFS DataNode dirs — so this checks every
    # non-system data disk uniformly. Kafka has its own separate Cloudera
    # filesystem-type guidance (ext4/xfs) that happens to agree with the
    # above, but no confirmed Cloudera source for the specific 1%
    # reserved-blocks number on a Kafka disk, so that number is labelled
    # as an HDFS/DataNode recommendation in the message text rather than
    # asserted as a universal requirement.
    #
    # A "data disk" here means any real block-device-backed mount
    # (findmnt source starting with /dev/) that is a directory and isn't
    # one of this host's standard OS partitions.
    local -a system_mounts=(/ /boot /boot/efi /home /opt /opt/cloudera /tmp /usr /usr/hdp /var /var/lib /var/log)

    local line source target fstype options is_system m
    while IFS= read -r line; do
        read -r source target fstype options <<< "$line"
        [ -z "$target" ] && continue
        [ -d "$target" ] || continue

        is_system=false
        for m in "${system_mounts[@]}"; do
            [ "$target" = "$m" ] && is_system=true && break
        done
        $is_system && continue

        local msg_prefix="System: data disk $target ($source, $fstype)"

        case "$fstype" in
            ext3|ext4|xfs)
                state "$msg_prefix uses a Cloudera-recommended extent-based filesystem" 0
                ;;
            *)
                state "$msg_prefix: $fstype is not a Cloudera-recommended data disk filesystem (ext3/ext4/xfs)" 2
                ;;
        esac

        if echo "$options" | tr ',' '\n' | grep -qx 'noatime'; then
            state "$msg_prefix mounted with noatime" 0
        else
            state "$msg_prefix not mounted with noatime (Cloudera recommendation)" 2
        fi

        if [ "$fstype" = "ext4" ]; then
            local resv_pct
            resv_pct=$(tune2fs -l "$source" 2>/dev/null | \
                awk '/^Reserved block count:/ {r=$4} /^Block count:/ {b=$3} END {if (b>0) printf "%.0f", (r/b)*100}')
            if [ -n "$resv_pct" ] && [ "$resv_pct" -le 1 ]; then
                state "$msg_prefix ext4 reserved blocks are ${resv_pct}% (<=1%, HDFS/DataNode recommendation)" 0
            else
                state "$msg_prefix ext4 reserved blocks should be reduced to 1% via 'mkfs -m1' (HDFS/DataNode recommendation). Actual: ${resv_pct:-unknown}%" 2
            fi
        fi
    done < <(findmnt -lno source,target,fstype,options | grep '^/dev')
}

function check_krb5_realms() {
    # KDC hostname resolution. In real CDP deployments the backing KDC is
    # very often Active Directory or FreeIPA, but kdc=/admin_server=
    # entries in /etc/krb5.conf's [realms] block are still commonly
    # assigned manually (not always left to dns_lookup_kdc DNS-SRV
    # discovery) — a copy-paste/typo'd hostname there is invisible until
    # Kerberos auth is actually attempted. This exercises standard
    # krb5.conf(5) semantics plus DNS, not a Cloudera-specific version or
    # OS threshold, so unlike the checks above it isn't tied to a single
    # docs.cloudera.com citation.
    # No-op if Kerberos isn't configured on this host at all. Note that
    # /etc/krb5.conf existing is NOT sufficient evidence of that: the
    # krb5-libs RPM ships a stub /etc/krb5.conf (fully commented-out
    # [realms]/default_realm) on every RHEL/Rocky host regardless of
    # whether Kerberos is actually in use, so a bare "-f /etc/krb5.conf"
    # gate produces a false FAIL on every non-Kerberized host. Require an
    # active (uncommented) default_realm in [libdefaults] instead, as the
    # signal that Kerberos is genuinely configured here.
    if [ ! -f /etc/krb5.conf ]; then
        return 0
    fi
    local default_realm
    default_realm=$(awk '/^[[:space:]]*\[libdefaults\]/{flag=1; next} /^[[:space:]]*\[/{flag=0} flag' /etc/krb5.conf | \
        grep -E '^[[:space:]]*default_realm[[:space:]]*=')
    if [ -z "$default_realm" ]; then
        return 0
    fi

    local realms_block
    realms_block=$(awk '/^[[:space:]]*\[realms\]/{flag=1; next} /^[[:space:]]*\[/{flag=0} flag' /etc/krb5.conf)

    if [ -z "$realms_block" ]; then
        state "System: /etc/krb5.conf has default_realm set but no [realms] section. Check skipped" 2
        return 0
    fi

    local -a entries=()
    local line key value host
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(kdc|admin_server)[[:space:]]*=[[:space:]]*(.+)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # strip trailing comment, then optional :port
        host=$(echo "$value" | sed -e 's/[[:space:]]*#.*$//' -e 's/:[0-9]*[[:space:]]*$//' -e 's/[[:space:]]*$//')
        [ -n "$host" ] && entries+=("$key:$host")
    done <<< "$realms_block"

    if [ ${#entries[@]} -eq 0 ]; then
        if grep -Eq '^[[:space:]]*dns_lookup_kdc[[:space:]]*=[[:space:]]*true' /etc/krb5.conf; then
            state "System: /etc/krb5.conf [realms] has no explicit kdc/admin_server entries; dns_lookup_kdc=true, relying on DNS SRV discovery. Check skipped" 2
        else
            state "System: /etc/krb5.conf [realms] has no explicit kdc/admin_server entries and dns_lookup_kdc is not enabled — Kerberos clients will not be able to locate a KDC" 1
        fi
        return 0
    fi

    local entry
    for entry in "${entries[@]}"; do
        key="${entry%%:*}"
        host="${entry#*:}"
        if [[ "$host" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || [[ "$host" == *:* ]]; then
            state "System: krb5.conf $key '$host' is a literal IP address, skipping DNS resolution check" 0
        elif getent hosts "$host" >/dev/null 2>&1; then
            state "System: krb5.conf $key '$host' resolves" 0
        else
            state "System: krb5.conf $key '$host' does not resolve — Kerberos authentication will fail against this host" 1
        fi
    done
}

function check_virt() {
        local msg="System: Non BareMetal deployments should follow appropriate Reference Architecures -- Please see https://bit.ly/2CTLeWB"
        case $(systemd-detect-virt) in
            none) state "System: Running on Bare Metal" 0;;
            *)                   state "$msg" 2;;
        esac
}

function checks() (
    print_header "Prerequisite checks"
    reset_service_state
    check_os
    check_sudo
    check_opt_cloudera_disk_space
    check_data_disk_mounts
    check_virt
    check_network
    check_firewall
    check_fapolicyd
    check_krb5_realms
    check_java
    check_python
    check_database
    check_jdbc_connector
)
