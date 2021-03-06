# Description:
#   Deploy commands.
#
# Commands:
#   hubot apps - Display app names.
#   hubot deploy <app> - Create deployment on OpsWorks.
#   hubot deploy-status <app> (num) - Show deployment status latest num number(default is 1).
#   hubot admin <app> - Invoke admin server on the app.
#   hubot dump  <app> - MySQL dump on the app.
#   hubot maintenance on <app> - Turn on maintenance mode
#   hubot maintenance off <app> - Turn off maintenance mode 

OpsWorks = require("../lib/opsworks")
ssh      = require('ssh2')
_        = require('underscore')
Q        = require('q')

unless process.env["HUBOT_PRIVATE_KEY"]
  throw 'env["HUBOT_PRIVATE_KEY"]が設定されていません'

module.exports = (robot) ->
  face = {
    normal:  '(´-ω-)'
    success: '(*´▽｀*)'
    failure: '(PД`q｡)'
  }

  robot.respond /APPS/i, (msg) ->
    OpsWorks.getApps().then (apps) -> msg.send apps.join(" ")
  
  robot.respond /DEPLOY (.*)$/i, (msg) ->
    app = msg.match[1]
    OpsWorks.use(app)
    .fail (err) ->
      msg.send "エラーですぅ #{face.failure} #{err.message}"
    .then (app) ->
      app.deploy().then (result) ->
        if result.DeploymentId
          msg.send "デプロイするよ #{face.success} https://console.aws.amazon.com/opsworks/home?#/stack/#{app.StackId}/deployments/#{result.DeploymentId}"
        else
          msg.send "デプロイできません #{face.failure}"


  robot.respond /DEPLOY[_\-]STATUS ([^ ]+)( ([0-9]+))?$/i, (msg) ->
    app = msg.match[1]
    num = msg.match[2]
    num -= 1 if num
    OpsWorks.use(app)
    .fail (err) ->
      msg.send "エラーですぅ #{face.failure} #{err.message}"
    .then (app) ->
      app.deployStatus(num).then (deploys) ->
        for deploy in deploys
          trans = {
            running:    "デプロイ中だよ #{face.normal}"
            successful: "終わったよ    #{face.success}"
            failed:     "失敗しちゃった #{face.failure}"}
          status = trans[deploy.Status]
          msg.send "#{status} https://console.aws.amazon.com/opsworks/home?#/stack/#{deploy.StackId}/deployments/#{deploy.DeploymentId}"

  run_ssh = (instance, cmd, finishCondition) ->
    deferred = Q.defer()    
    session = new ssh()
    session.on 'ready', () ->
      session.exec cmd, {pty: true}, (err, stream) ->
        stream.on 'data', (data, extended) ->
          result = data.toString()
          if finishCondition(result)
            stream.destroy() 
        stream.on 'end', () ->
          deferred.resolve()
          session.end()
    session.on 'error', () ->
      deferred.reject()
    session.connect
      host: instance.PublicIp
      port: 22
      username: 'deploy'
      privateKey: process.env["HUBOT_PRIVATE_KEY"]
    deferred.promise

  robot.respond /maintenance on (.*)$/i, (msg) ->
    app = msg.match[1]

    OpsWorks.use(app)
    .fail (err) ->
      msg.send "エラーですぅ #{face.failure} #{err.message}"
    .then (app) ->
      app.detachELB()
      .then (response) -> msg.send "メンテナンス ✧＼\ ٩( 'ω' )و /／✧ オン!!"
      .fail (response) -> msg.send "何かエラーでした orz\n#{response}"
      .done () -> msg.send "処理しゅーりょー"
          
  robot.respond /maintenance off (.*)$/i, (msg) ->
    app = msg.match[1]
    o = OpsWorks.use(app)
    .fail (err) ->
      msg.send "エラーですぅ #{face.failure} #{err.message}"
    .then (app) ->
      app.attachELB()
      .then (response) -> msg.send "メンテナンス (｡´-д-) オフ!!"
      .fail (response) -> msg.send "何かエラーでした orz\n#{response}"
      .done () -> msg.send "処理しゅーりょー"

  robot.respond /ADMIN (.*)$/i, (msg) ->
     app = msg.match[1]
     OpsWorks.use(app)
     .fail (err) ->
       msg.send "エラーですぅ #{face.failure} #{err.message}"
     .then (app) ->
       app.instances().then (instances) ->
         instance = _.find instances, (instance) -> instance.Status == 'online'
         railsEnv = if app.Name.match(/stg/) then "staging" else "production"
         cmd = """
           SERVER_PROCESS=$(ps ax | grep ruby | grep rails | grep -v bash |  awk '{print $1}')
           if [ -n "$SERVER_PROCESS" ];then
             kill $SERVER_PROCESS
           fi
           cd /srv/www/#{app.Name}/current
           RAILS_ENV=#{railsEnv} ALLOW_ADMIN=1 nohup bundle exec rails s
         """
         run_ssh(instance, cmd, (result) -> result.match(/nohup\.out/))
           .done () ->
             voice = """
             $ ssh -N -L 8888:localhost:3000 deploy@#{instance.PublicIp} を起動
             http://localhost:8888/admin にアクセスだ! （｀・ω・´）
             """
             msg.send voice
           .fail () ->
             msg.send "SSHでエラーっす #{face.failure}"        

  robot.respond /dump (.*)$/i, (msg) ->
     app = msg.match[1]
     dump_path="/home/deploy/#{app}.dump"
     OpsWorks.use(app)
     .fail (err) ->
       msg.send "エラーですぅ #{face.failure} #{err.message}"
     .then (app) ->
       app.instances().then (instances) ->
         instance = _.find instances, (instance) -> instance.Status == 'online'
         railsEnv = if app.Name.match(/stg/) then "staging" else "production"
         cmd = """
           YAML=$(cat /srv/www/#{app.Name}/current/config/database.yml)
           HOST=$(echo "$YAML" | grep host: | head -1 | awk '{print $2}' | sed -e 's/"//g')
           USER=$(echo "$YAML" | grep username: | head -1 | awk '{print $2}' | sed -e 's/"//g')
           PASS=$(echo "$YAML" | grep password: | head -1 | awk '{print $2}' | sed -e 's/"//g')
           DB=$(echo "$YAML" | grep database: | head -1 | awk '{print $2}' | sed -e 's/"//g')
           mysqldump -h "$HOST" -u "$USER" --password="$PASS" "$DB" > #{dump_path}
         """
         run_ssh(instance, cmd, (result) -> result.match(/nohup\.out/))
           .done () ->
             voice = """
               $ rsync -avz -e ssh deploy@#{instance.PublicIp}:#{dump_path} . でデータ取得できるよー#{face.success}
             """
             msg.send voice
           .fail () ->
             msg.send "SSHでエラーっす #{face.failure}"
