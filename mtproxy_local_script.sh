sudo apt update && sudo apt install -y git curl build-essential libssl-dev zlib1g-dev
git clone https://github.com/GetPageSpeed/MTProxy && cd MTProxy
sudo sed -i "s/-fwrapv/-fwrapv -fcommon/" ~/MTProxy/Makefile
sudo sed -i "s/-lpthread -lcrypto/-lpthread -lcrypto -fcommon/" ~/MTProxy/Makefile
cd ~/MTProxy/ && make
sudo mkdir /opt/MTProxy && sudo cp objs/bin/mtproto-proxy /opt/MTProxy/ && cd /opt/MTProxy
sudo curl -s https://core.telegram.org/getProxySecret -o proxy-secret
sudo curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
sudo useradd -m -s /bin/false mtproxy && sudo chown -R mtproxy:mtproxy /opt/MTProxy
sudo ufw allow 8443/tcp
secret=$(head -c 16 /dev/urandom | xxd -ps)
mypubip=$(curl https://ifconfig.me) && echo $mypubip
privip=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d'/' -f1) && echo $privip

mtproxy_service=~/MTProxy.service
cat <<EOT > $mtproxy_service
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/mtproto-proxy -u mtproxy -p 8888 -H 8443 -S ${secret} --aes-pwd proxy-secret proxy-multi.conf -M 1 --http-stats --nat-info ${privip}:${mypubip}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

sudo cp ~/MTProxy.service /etc/systemd/system/MTProxy.service
sudo systemctl daemon-reload && sudo systemctl restart MTProxy.service && sudo systemctl status MTProxy.service

echo "You can use this URL for MTPROXY: https://t.me/proxy?server=${mypubip}&port=8443&secret=${secret}"

rm $mtproxy_service
