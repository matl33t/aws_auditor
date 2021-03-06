# SportNginAwsAuditor

Audits your AWS accounts to find discrepancies between the number of running instances and purchased reserved instances.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sport_ngin_aws_auditor'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sport_ngin_aws_auditor

## How-to

### AWS Setup
Either create an `~/.aws/credentials` file that should have the following structure:

```
[ACCOUNT 1]
aws_access_key_id = [AWS ACCESS KEY]
aws_secret_access_key = [SECRET ACCESS KEY]

[ACCOUNT 2]
aws_access_key_id = [AWS ACCESS KEY]
aws_secret_access_key = [SECRET ACCESS KEY]

[ACCOUNT 3]
aws_access_key_id = [AWS ACCESS KEY]
aws_secret_access_key = [SECRET ACCESS KEY]
```

Then this gem will use [AWS Shared Credentials](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) with your credentials file. However, if you'd like to run these through either a default profile in your credentials file or through [User Roles](http://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html), then use the flag `aws_roles`:

    $ sport-ngin-aws-auditor --aws_roles [command] account1

### Google Setup (optional)
You can export audit information to a Google Spreadsheet, but you must first follow “Create a client ID and client secret” on [this page](https://developers.google.com/drive/web/auth/web-server) to get a client ID and client secret for OAuth. Then create a `.google.yml` in your home directory with the following structure.

```yaml
---
credentials:
  client_id: 'GOOGLE_CLIENT_ID'
  client_secret: 'GOOGLE_CLIENT_ID'
file:
  path: 'DESIRED_PATH_TO_FILE' # optional, creates in root directory otherwise
  name: 'NAME_OF_FILE'
```
 
## Usage

### The Audit Command

To find discrepancies between number of running instances and purchased instances, run:

    $ sport-ngin-aws-auditor audit account1

Any running instances that are not matched with a reserved instance with show up as yellow (with the negative number indicating the amount), the reserved instances that are not matched with an running instance will show up in red (with the positive number indicating the amount), and any reserved instances and running instances that match will show up in green. Any instances in blue with asteriks have a special tag that can either be specified in the audit command or will be defaulted to `no-reserved-instance`.

To specify your own tag name, run:

    $ sport-ngin-aws-auditor audit --tag=your_custom_tag account1

If you don't want to use any tag at all, run:

    $ sport-ngin-aws-auditor audit --no_tag account1

To print a condensed version of the discrepancies to a Slack account (instead of printing to the terminal), run:

    $ sport-ngin-aws-auditor audit --slack account1

For this option to use a designated channel, username, icon/emoji, and webhook, set up a global config file that should look like this:

```
slack:
  username: [AN AWESOME USERNAME]
  icon_url: [AN AWESOME IMAGE]
  channel: "#[AN SUPER COOL CHANNEL]"
  webhook: [YOUR WEBHOOK URL]
```

The default is for the file to be called `.aws_auditor.yml` in your home directory, but to pass in a different path, feel free to pass it in via command line like this:

    $ sport-ngin-aws-auditor --config="/PATH/TO/FILE/slack_file_creds.yml" audit --slack staging

The webhook urls for slack can be obtained [here](https://api.slack.com/incoming-webhooks).

### The Inspect Command

To list information about all running instances in your account, run:

    $ sport-ngin-aws-auditor inspect account1

### The Export Command

To export audit information to a Google Spreadsheet, make sure you added a `.google.yml` and run:

    $ sport-ngin-aws-auditor export -d account1
    
## Contributing

1. Fork it (https://github.com/sportngin/sport_ngin_aws_auditor/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
