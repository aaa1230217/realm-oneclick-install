#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root用户来执行脚本!" && exit 1

disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

getversion(){
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

centosversion(){
    if check_sys sysRelease centos; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

download(){
    local filename=${1}
    echo -e "[${green}Info${plain}] ${filename} download now..."
    wget --no-check-certificate -q -t3 -T60 -O ${1} ${2}
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Download ${filename} failed."
        exit 1
    fi
}

error_detect_depends(){
    local command=$1
    local depend=`echo "${command}" | awk '{print $4}'`
    echo -e "[${green}Info${plain}] Starting to install package ${depend}"
    ${command} 
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Failed to install ${red}${depend}${plain}"
        exit 1
    fi
}

install_dependencies(){
    if centosversion 8; then
	    echo "检测到系统为CentOS 8，正在更新源。使用vault.centos.org代替mirror.centos.org..."
        sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
	    sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
    fi
	
	if check_sys packageManager yum; then
		error_detect_depends "yum -y install wget"  
	elif check_sys packageManager apt; then
		error_detect_depends "apt-get -y install wget"
	fi	
}

hello(){
    echo ""
    echo -e "${yellow}realm自助安装脚本${plain}"
	echo "realm is a simple, high performance relay server written in rust."
	echo "项目地址：https://github.com/zhboner/realm"
    echo ""
}

help(){
    hello
    echo "使用方法：bash $0 [-h] [-i] [-u]"
    echo ""
    echo "  -h , --help                显示帮助信息"
    echo "  -i , --install             安装realm"
    echo "  -u , --uninstall           卸载realm"
    echo ""
}

confirm(){
    echo -e "${yellow}是否继续执行?(n:取消/y:继续)${plain}"
    read -e -p "(默认:取消): " selection
    [ -z "${selection}" ] && selection="n"
    if [ ${selection} != "y" ]; then
        exit 0
    fi
}

install_realm(){
	echo "安装realm zhboner2.+版本..."
	
	download  /usr/local/bin/realm  https://github.com/aaa1230217/realm-oneclick-install/releases/download/V2.4.1/realm && chmod +x /usr/local/bin/realm
	download  /etc/systemd/system/realm.service  https://raw.githubusercontent.com/aaa1230217/realm-oneclick-install/main/realm.service
	[ ! -d /etc/realm/ ] && mkdir /etc/realm/
	download  /etc/realm/config.json  https://raw.githubusercontent.com/aaa1230217/realm-oneclick-install/main/config.json
	wget  https://raw.githubusercontent.com/aaa1230217/RealM_Jiaoben_Fork/master/realm.sh && chmod +x realm.sh
	
	echo "realm zhboner2.+安装成功..."
	[ -f /usr/local/bin/realm ] && echo -e "${green}installed${plain}: /usr/local/bin/realm"
	[ -f /etc/systemd/system/realm.service ] && echo -e "${green}installed${plain}: /etc/systemd/system/realm.service"
	[ -f /etc/realm/config.json ] && echo  -e "${green}installed${plain}: /etc/realm/config.json"
	
	echo -e "${yellow}注意：本脚本没有自动配置转发，也没有启动realm。${plain}"
	echo -e "${yellow}请编辑/etc/realm/config.json，添加转发配置。${plain}"
	echo -e "${yellow}运行命令 systemctl enable --now realm && systemctl start realm 启动realm${plain}"
}

uninstall_realm(){
    systemctl stop realm
    systemctl disable realm

	rm -f /usr/local/bin/realm
	rm -f /etc/systemd/system/realm.service
	rm -rf /etc/realm/
	
	if [ ! -f /usr/local/bin/realm ] && [ ! -f /etc/systemd/system/realm.service ] && [ ! -f /etc/realm/config.json ];then 
		echo -e "${green}卸载成功${plain}"
	else 
	    echo -e "${red}卸载失败${plain}"
	fi
}

if [[ $# = 1 ]];then
    key="$1"
    case $key in
        -i|--install)
		disable_selinux
		install_dependencies
        install_realm
        ;;
        -u|--uninstall)
		hello
        echo -e "${yellow}正在执行卸载realm.${plain}"
        confirm
        uninstall_realm
        ;;
        -h|--help|*)
        help
        ;;
    esac
else
    help
fi
