# dockerコンテナを使ったオンデマンド起動のPoC

## h2oからの操作

### h2o/mruby を介して、コンテナをオンデマンドに起動する

```
curl http://localhost:8080/start_and_access_docker_container
```

## 操作するAPI(dondemand)について

Docker Remote API を使って、コンテナの開始、停止の操作を行う簡易的なアプリケーション
docker-compose.yml では、Remote APIを sock-proxyコンテナを介して操作します

### ある1つのコンテナを停止する

```
curl -X DELETE localhost:5000/app_sample
```

### 直近でアクセスがないコンテナを停止する

```
curl -X PURGE localhost:5000/(APIKEY)
```

### 操作対象のコンテナすべてを停止する

```
curl -X PURGE localhost:5000/(APIKEY)?force=1
```

## h2o/dondemand.rb について

起動した後に、API(dondemand)から応答があるので、その応答を持って、後段に定義されたproxy先へ遷移する

## dondemand_purge について

cronのような動きをして、定期的にcurlでdondemandにリクエストする

アクセスが無くなった(このPoCでは30秒アクセスがされなくなったら)コンテナを停止させる

