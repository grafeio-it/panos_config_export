FW="https://192.168.0.11"
USER="username"
PASS='password'    

curl -vk --connect-timeout 5 --max-time 20 -G "$FW/api/" \
  --data-urlencode "type=keygen" \
  --data-urlencode "user=$USER" \
  --data-urlencode "password=$PASS"
