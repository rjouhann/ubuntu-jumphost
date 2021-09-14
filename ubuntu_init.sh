#!/bin/bash
# Uncomment set command below for code debugging bash
#set -x

##### INSTALLATION
# Download and install the script under /home/$USER (e.g. ubuntu)
# rm -f ubuntu_init.sh
# curl -o ubuntu_init.sh https://raw.githubusercontent.com/rjouhann/ubuntu-jumphost/main/ubuntu_init.sh
# chmod +x ubuntu_init.sh

# Set password
# echo "secret" > /home/$USER/.secret

# Add in $USER's crontab so script start at boot
# @reboot sleep 900 && /home/$USER/ubuntu_init.sh > /home/ubuntu_init.log 2>&1


##### CONFIGURATION
password="$(cat /home/$USER/.secret)"
external_nic="ens6"
external_ip="10.1.10.5/24"
internal_nic="ens7"
internal_ip="10.1.20.5/24"
internal_ip1="10.1.20.100/24"
internal_ip2="10.1.20.101/24"
internal_ip3="10.1.20.102/24"
internal_ip4="10.1.20.103/24"

##### SCRIPT

# SECONDS used for total execution time (see end of the script)
SECONDS=0

cd /home/$USER

sudo apt update

sudo docker info
if [ $? == 0 ];then
    echo -e "\nInstall Docker"
    sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo apt-key fingerprint 0EBFCD88
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install docker-compose -y
    sudo systemctl unmask docker.service
    sudo systemctl unmask docker.socket
    sudo systemctl start docker.service
    sudo docker version
    sudo docker info
    sudo docker network ls
    sudo gpasswd -a $USER docker
fi

echo "Install Netplan (if no already installed)"
sudo apt install netplan.io -y

ip addr | grep "$internal"
if [ $? == 0 ];then
    echo "Configure Netplan"
    sudo bash -c "echo \"network:
  version: 2
  ethernets:
    $external_nic:
        addresses:
            - $external_ip
    $internal_nic:
        addresses:
            - $internal_ip
            - $internal_ip1
            - $internal_ip2
            - $internal_ip3
            - $internal_ip4\" > /etc/netplan/01-netcfg.yaml"

    sudo cat /etc/netplan/01-netcfg.yaml

    sudo netplan generate
    sudo netplan try
    echo
    ip addr
fi

echo -e "\nInstall Apache Benchmark, Git, jq, unzip (if no already installed)"
sudo sudo sudo apt install apache2-utils -y
apt install git git-lfs -y
apt install jq -y
sudo apt install unzip -y

echo -e "\nInstall Ansible and sshpass (if no already installed)"
sudo apt install ansible -y
sudo apt install sshpass -y
ansible-playbook --version

# Cleanup any existing docker
sudo docker ps
sudo docker stop $(docker ps -q)
sudo docker kill $(docker ps -q)
sudo docker rm $(docker ps -a -q)

# Juice Shop - https://owasp.org/www-project-juice-shop/
sudo docker run --restart=always --name=juice-shop -dit -p 3000:3000 bkimminich/juice-shop

# Firefox
sudo docker run -d --name=firefox -p 5800:5800 -v /etc/hosts:/etc/hosts -v /docker/appdata/firefox:/config:rw --shm-size 2g jlesage/firefox

# Syslog server
sudo docker run --restart=always --name=syslog -dit -e SYSLOG_USERNAME=admin -e SYSLOG_PASSWORD=$password -p 5801:80 -p 514:514/udp pbertera/syslogserver

### Visual Studio Code https://github.com/cdr/code-server
sudo docker pull codercom/code-server:latest
sudo docker run --restart=always --name=code-server -d -p 5802:8080 -e PASSWORD="$password" -v "/home/$USER:/home/coder/project" codercom/code-server:latest
sudo docker exec code-server sh -c "sudo apt-get update"
sudo docker exec code-server sh -c "sudo apt-get install -y python3 python3-dev python3-pip python3-jmespath"
sudo docker exec code-server sh -c "pip3 install ansible"

# Download latest https://github.com/f5devcentral/vscode-f5
wget $(curl -s https://api.github.com/repos/f5devcentral/vscode-f5/releases/latest | grep browser_download_url | grep '.vsix' | head -n 1 | cut -d '"' -f 4)
sudo docker cp *.vsix code-server:/tmp
sudo docker exec code-server code-server --install-extension /tmp/$(ls *vsix)
sudo docker exec code-server sh -c "rm -f /tmp/*vsix"
rm *.vsix

# Download latest https://github.com/f5devcentral/vscode-f5-chariot
wget $(curl -s https://api.github.com/repos/f5devcentral/vscode-f5-chariot/releases/latest | grep browser_download_url | grep '.vsix' | head -n 1 | cut -d '"' -f 4)
sudo docker cp *.vsix code-server:/tmp
sudo docker exec code-server code-server --install-extension /tmp/$(ls *vsix)
sudo docker exec code-server sh -c "rm -f /tmp/*vsix"
rm *.vsix

# Download latest https://github.com/f5devcentral/vscode-nim
wget $(curl -s https://api.github.com/repos/f5devcentral/vscode-nim/releases/latest | grep browser_download_url | grep '.vsix' | head -n 1 | cut -d '"' -f 4)
sudo docker cp *.vsix code-server:/tmp
sudo docker exec code-server code-server --install-extension /tmp/$(ls *vsix)
sudo docker exec code-server sh -c "rm -f /tmp/*vsix"
rm *.vsix

echo '{"folders":[{"path":".."}],"files.exclude":{"**/.*":true,"**/settings_vscode.json":true}}' > /home/$USER/settings_vscode.json
cat /home/$USER/settings_vscode.json | jq .

sudo docker exec code-server code-server --install-extension dawhite.mustache
sudo docker exec code-server code-server --install-extension humao.rest-client
sudo docker exec code-server code-server --install-extension vscoss.vscode-ansible
sudo docker exec code-server code-server --list-extensions
sudo docker exec code-server mkdir /home/coder/.vscode
sudo docker exec code-server cp /home/coder/project/settings_vscode.json /home/coder/.vscode/settings.json
sudo docker restart code-server 

## Locust/Traffic Generator: https://locust.io
mkdir /home/$USER/locust
cat <<EOT >> /home/$USER/locust/locustfile.py
import time
from locust import HttpUser, task, between

# https://docs.locust.io/en/stable/quickstart.html

class QuickstartUser(HttpUser):
    wait_time = between(5, 10)

    @task
    def index_page(self):
        self.client.get("/", verify=False)
EOT

sudo docker run --restart=unless-stopped --name=locust -dit -p 5803:8089 -v /home/$USER/locust:/mnt/locust locustio/locust -f /mnt/locust/locustfile.py --host http://10.1.10.100:3000

sudo docker ps

# total script execution time
echo -e "$(date +'%Y-%d-%m %H:%M'): elapsed time: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
