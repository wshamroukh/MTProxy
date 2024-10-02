
# https://github.com/mtproxy/update
#variables
rg='mtproxy'
location='centralindia'
vm_name='mtproxy'
vm_image=$(az vm image list -l $location -p Canonical -s 22_04-lts --all --query "[?offer=='0001-com-ubuntu-server-jammy'].urn" -o tsv | sort -u | tail -n 1) && echo $vm_image
vnet_name='mtproxy-vnet'
vnet_address='10.10.1.0/24'
lan_subnet_name='lan-subnet'
lan_subnet_address='10.10.1.0/24'
vm_size=Standard_B2ats_v2
admin_username=$(whoami)
admin_password='Test#123#123'

# resource group
echo -e "\e[1;36mCreating Resource Group $rg...\e[0m"
az group create -n $rg -l $location -o none

# vnet
echo -e "\e[1;36mCreating VNet $vnet_name...\e[0m"
az network vnet create -g $rg -n $vnet_name --address-prefixes $vnet_address --subnet-name $lan_subnet_name --subnet-prefixes $lan_subnet_address -o none

# vm
echo -e "\e[1;36mCreating $vm_name VM...\e[0m"
az network public-ip create -g $rg -n "$vm_name-public-ip" --allocation-method Static --sku Basic -o none
az network nic create -g $rg -n "$vm_name-lan-nic" --subnet $lan_subnet_name --vnet-name $vnet_name --private-ip-address 10.10.1.250 --public-ip-address "$vm_name-public-ip" -o none
az vm create -g $rg -n $vm_name --image $vm_image --nics "$vm_name-lan-nic" --os-disk-name $vm_name-osdisk --size $vm_size --admin-username $admin_username --generate-ssh-keys

# vm details
mtproxy_public_ip=$(az network public-ip show -g $rg -n "$vm_name-public-ip" --query 'ipAddress' --output tsv) && echo $vm_name public ip address: $mtproxy_public_ip
mtproxy_private_ip=$(az network nic show -g $rg -n "$vm_name-lan-nic" --query ipConfigurations[].privateIPAddress -o tsv) && echo $vm_name private IP: $mtproxy_private_ip

script_file=~/script.sh
cat <<EOF > $script_file
sudo apt update && sudo apt install -y git curl build-essential libssl-dev zlib1g-dev
git clone https://github.com/GetPageSpeed/MTProxy && cd MTProxy
sudo sed -i "s/-fwrapv/-fwrapv -fcommon/" /home/$admin_username/Make
sudo sed -i "s/-lpthread -lcrypto/-lpthread -lcrypto -fcommon/" /home/$admin_username/MTProxy/Make
cd /home/$admin_username/MTProxy/ && make
sudo mkdir /opt/MTProxy && sudo cp objs/bin/mtproto-proxy /opt/MTProxy/ && cd /opt/MTProxy
sudo curl -s https://core.telegram.org/getProxySecret -o proxy-secret
sudo curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
sudo useradd -m -s /bin/false mtproxy && sudo chown -R mtproxy:mtproxy /opt/MTProxy
sudo ufw allow 8443/tcp
EOF

mtproxy_service=~/MTProxy.service
tee -a $mtproxy_service > /dev/null <<'EOT'
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/mtproto-proxy -u mtproxy -p 8888 -H 8443 -S $secret --aes-pwd proxy-secret proxy-multi.conf -M 1 --http-stats --nat-info $mtproxy_private_ip:$mtproxy_public_ip
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

sed -i "/\$secret/ s//$secret/" $mtproxy_service
sed -i "/\$mtproxy_private_ip/ s//$mtproxy_private_ip/" $mtproxy_service
sed -i "/\$mtproxy_public_ip/ s//$mtproxy_public_ip/" $mtproxy_service

# installation and configuration of mtproxy 
echo -e "\e[1;36mCopying configuration files to $vm_name and installing mtproxy firewall...\e[0m"
scp -o StrictHostKeyChecking=no $script_file $mtproxy_service $admin_username@$mtproxy_public_ip:/home/$admin_username
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "secret=\$(head -c 16 /dev/urandom | xxd -ps) && sed -i \"s/\\\$secret/\$secret/\" ~/MTProxy.service && echo You can use this URL for MTPROXY: https://t.me/proxy?server=\\$mtproxy_public_ip\&port=8443\&secret=\$secret"
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "sed -i \"s/\\\$mtproxy_private_ip/$mtproxy_private_ip/\" ~/MTProxy.service"
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "sed -i \"s/\\\$mtproxy_public_ip/$mtproxy_public_ip/\" ~/MTProxy.service"
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "sudo cp /home/$admin_username/MTProxy.service /etc/systemd/system/MTProxy.service"
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "chmod +x /home/$admin_username/script.sh && sh /home/$admin_username/script.sh"
ssh -o StrictHostKeyChecking=no $admin_username@$mtproxy_public_ip "sudo systemctl daemon-reload && sudo systemctl restart MTProxy.service && sudo systemctl status MTProxy.service"
rm $script_file $mtproxy_service
