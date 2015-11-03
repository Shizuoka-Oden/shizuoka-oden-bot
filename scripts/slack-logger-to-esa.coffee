# slackのログをesaに登録するボット。
# お昼の１２時に動きます。

_ = require('lodash');
CronJob = require('cron').CronJob;
request = require('request');

# 環境変数からトークンやチーム名を読み込む
SLACK_API_TOKEN = process.env.HUBOT_ENV_SLACK_API_TOKEN
ESA_API_TOKEN = process.env.HUBOT_ENV_ESA_API_TOKEN
ESA_TEAM_NAME = process.env.HUBOT_ENV_ESA_TEAM_NAME

# SLACK API
SLACK_API_URL = "https://slack.com/api"
SLACK_API_USERS_LIST_URL = "#{SLACK_API_URL}/users.list?token=#{SLACK_API_TOKEN}"
SLACK_API_CHANNELS_LIST_URL    = "#{SLACK_API_URL}/channels.list?token=#{SLACK_API_TOKEN}"
SLACK_API_CHANNELS_HISTORY_URL = "#{SLACK_API_URL}/channels.history?token=#{SLACK_API_TOKEN}"

# ESA API
ESA_API_URL = "https://api.esa.io"
ESA_API_POSTS_URL = "#{ESA_API_URL}/v1/teams/#{ESA_TEAM_NAME}/posts?access_token=#{ESA_API_TOKEN}"

NOTICE_CHANNEL = "hubot-test"
IGNORE_CHANNEL = "hubot-test"

# 前日分のメッセージを取得するURLを取得する
getChannelHistoryUrl = (channelId) -> 
  d = new Date
  y = d.getFullYear()
  m = d.getMonth()
  d = d.getDate()
  latest = new Date(y, m, d).getTime() / 1000
  oldest = latest - 60 * 60 * 24
  SLACK_API_CHANNELS_HISTORY_URL + "&channel=#{channelId}&oldest=#{oldest}&latest=#{latest}&count=1000&inclusive=1"

# メッセージのtsから時間文字列(hh:mm:ss)を取得する
getTimeStringFromMessageTs = (messageTs) -> 
  ts = messageTs.split(".")[0] * 1000
  d = new Date(ts)
  ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2) + ":" + ("0" + d.getSeconds()).slice(-2)


notice = (robot, message) ->
  robot.messageRoom NOTICE_CHANNEL, message

noticeAlert = (robot, body, message) ->
  robot.messageRoom NOTICE_CHANNEL, "WARNING!! WARNING!! #{message} \r\n CODE : #{body.error}  MESSAGE : + #{body.message}"

job = (robot, targetChannel) ->
  notice(robot, "サクジツ ノ ログ サイシュヲ カイシ イタシマス。ピーガガガ。。。")
  console.log "job start"

  # ユーザ一覧を取得
  console.log "get users"
  request.get SLACK_API_USERS_LIST_URL, (error, response, body) ->
    if error || response.statusCode != 200
      noticeAlert(robot, body, "メンバー シュトク シッパイ。")
      return
    users = {}
    members = JSON.parse(body).members
    members.forEach (member) ->
      users[member.id] = member.name

    # チャンネル一覧を取得
    console.log "get channels"
    request.get SLACK_API_CHANNELS_LIST_URL, (error, response, body) ->
      if error || response.statusCode != 200
        noticeAlert(robot, body, "チャンネル シュトク シッパイ。")
        return
      channels = JSON.parse(body).channels


      # チャンネル毎のメッセージを取得
      channels.forEach (channel) ->
        if channel.name == IGNORE_CHANNEL
          console.log "#{channel.name} is ignore channnel"
          return

        if channel.name != targetChannel && targetChannel != "all"
          console.log "not target #{targetChannel} channel -> #{channel.name}"
          return

        console.log "get log messages channel -> #{channel.name}"
        request.get getChannelHistoryUrl(channel.id), (error, response, body) ->
          if error || response.statusCode != 200
            noticeAlert(robot, body, "ログ シュトク シッパイ。")
            return

          # メッセージは降順で取得（ソートの指定はできなそう）なので昇順にする
          messages = _.sortBy(JSON.parse(body).messages, 'ts');
          if _.isEmpty(messages)
            console.log "no messages. channel -> #{channel.name}"
            return

          # slackログをesaのリクエスト形式に変換
          body_md = ""
          messages.forEach (message) ->
            body_md += "#{getTimeStringFromMessageTs(message.ts)} (#{users[message.user]})\t#{message.text}\r\n"

          oneDayAgo = new Date
          oneDayAgo.setDate(oneDayAgo.getDate() - 1)
          log = {
               "post":{
                  "name" : oneDayAgo.getDate(),
                  "body_md" : body_md,
                  "tags" : ["slacklog"],
                  "category" : "slacklog/#{channel.name}/#{oneDayAgo.getFullYear()}/#{oneDayAgo.getMonth() + 1}",
                  "wip" : true
               }
            }
 
          # esaにslackログを登録する
          request {method : 'POST', uri : ESA_API_POSTS_URL, json : log}, (error, response, body) ->
            if error || response.statusCode != 201
              console.log "faild to post log messages to esa. channel -> #{channel.name}"
              console.log JSON.stringify(response)
              noticeAlert robot, body, "ログ トウロク シッパイ。 #{channel.name}"
              return
            console.log "post log messages to esa. channel -> #{channel.name}"

module.exports = (robot) ->

  robot.hear /slacklog$/i, (msg) ->
    job(robot, "all")

  robot.hear /slacklog (.*)/i, (msg) ->
    job(robot, msg.match[1])

  cron = new CronJob '0 0 12 * * *', () => 
      job(robot)
    ,
    null,
    false,
    'Asia/Tokyo'
  cron.start()
