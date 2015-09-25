#!/usr/bin/env ruby

require 'phabricator'
require 'json'
require 'open3'


# Helpers

# Runs a conduit function with the given input (which is automatically converted
# to JSON) and returns the JSON-parsed response. Aborts the script if the
# function fails.
def run_conduit conduit_function, input={}
  input_json = JSON.dump input

  command_parts = ["arc", "call-conduit", "--conduit-token", $conduit_token, conduit_function]
  stdout, stderr, status = Open3.capture3 *command_parts, stdin_data: input_json

  unless status.success?
    # could not call arc call-conduit
    STDERR.puts 'Conduit function returned a non-zero exit code:'
    STDERR.puts "echo '#{input_json}' | #{command_parts.join ' '}"
    STDERR.puts stdout, stderr
    abort
  end

  parsed_output = JSON.load stdout

  if parsed_output['error']
    # conduit call failed
    STDERR.puts 'Conduit function returned a non-zero exit code:'
    STDERR.puts "echo '#{input_json}' | #{command_parts.join ' '}"
    STDERR.puts parsed_output['errorMessage']
    abort
  end

  # success, return the parsed result
  parsed_output['response']
end

# returns a map of lowercase name -> PHID for all users in phabricator
def get_users
  Hash[run_conduit('user.query').map do |user|
    [user['realName'].downcase, user['phid']]
  end]
end

# given an asana user's id and name, and the return value of get_users, returns
# the PHID of the phabricator user that corresponds to the asana user.
#
# Right now, we match this only on name, but the idea is that we could modify
# this function and get_users do to a different kind of matching.
def match_user asana_id, asana_name, all_users
  return all_users[asana_name.downcase]
end

# creates a task and returns its PHID
def create_task name, assignee, description, due_date
  due_date_str = due_date ? due_date.strftime('%s') : nil

  result = run_conduit "maniphest.createtask", {
    "title" => name,
    "ownerPHID" => assignee,
    "description" => description,
    "auxiliary" => {
      "std:maniphest:tulip:due-date" => due_date_str
    }
  }

  return result["phid"]
end

# Creates a sub-task and returns its PHID
def create_subtask parent_phid, name, assignee, description, due_date
  unless assignee
    # get assignee from parent task
    assignee = run_conduit('maniphest.query', phids: [parent_phid])[parent_phid]["ownerPHID"]
  end

  parent_name = run_conduit('maniphest.query', phids: [parent_phid])[parent_phid]["title"]

  name_with_parent = "#{parent_name} - #{name}"

  due_date_str = due_date ? due_date.strftime('%s') : nil

  result = run_conduit "maniphest.createtask", {
    "title" => name_with_parent,
    "ownerPHID" => assignee,
    "description" => description,
    "auxiliary" => {
      "std:maniphest:tulip:due-date" => due_date_str
    }
  }

  return result["phid"]
end


# creates a new comment on a task
def create_comment task_phid, author_name, body
  body_with_author = "#{author_name} commented on Asana:\n\n#{body}"

  run_conduit "maniphest.update", phid: task_phid, comments: body_with_author
end

# given a task from the Asana JSON, returns the URL for that task
def get_asana_url asana_task
  return "https://app.asana.com/0/#{asana_task["projects"][0]["id"]}/#{asana_task["id"]}"
end

# given a task from the Asana JSON, imports it into Phabricator
def migrate_asana_task asana_task, parent_phid, parent_url, all_users
  return if asana_task["completed"]

  name = asana_task["name"]
  url = parent_url || get_asana_url(asana_task)

  description = "#{asana_task["notes"]}\n\nImported from Asana: #{url}"


  assignee = if asana_task["assignee"]
               match_user asana_task["assignee"]["id"], asana_task["assignee"]["name"], all_users
             else
               nil
             end

  due_date = if asana_task["due_on"]
               DateTime.parse asana_task["due_on"]
             else
               nil
             end

  if parent_phid
    new_phid = create_subtask parent_phid, name, assignee, description, due_date
  else
    new_phid = create_task name, assignee, description, due_date
  end

  if asana_task["subtasks"]
    asana_task["subtasks"].each do |subtask|
      migrate_asana_task subtask, new_phid, url, all_users
    end
  end

  if asana_task["stories"]
    asana_task["stories"].select do |story|
      story["type"] == "comment"
    end.each do |comment|
      create_comment new_phid, comment["created_by"]["name"], comment["text"]
    end
  end
end

class MiniProgress
  SPINNER = ['|', '/', '-', '\\']
  UPDATE_FREQUENCY_SECONDS = 0.5

  def initialize total
    # total number of items to process
    @total = total

    # index of the spinner state within SPINNER
    @spinner_pos = 0

    # time at which we last printed a status update
    @last_progress_update_time = nil

    # number of items we've processed
    @num_completed = 0
  end

  def next
    @num_completed += 1

    if @last_progress_update.nil? or (Time.now - @last_progress_update) > UPDATE_FREQUENCY_SECONDS
      STDERR.print "\r#{SPINNER[@spinner_pos]}    %6d / %6d (%6.2f%%)" % [@num_completed, @total, (@num_completed.to_f / @total * 100)]
      @spinner_pos = (@spinner_pos + 1) % SPINNER.length
      @last_progress_update = Time.now
    end
  end
end


if __FILE__ == $0

  # Argument handling
  ASANA_EXPORT_FILE = ARGV[0]
  $conduit_token = ARGV[1]

  if (ASANA_EXPORT_FILE == "-h") or (ASANA_EXPORT_FILE == "--help")
    puts "Usage: import.rb <asana_export.json> <conduit-token>"
    exit 0
  end

  unless $conduit_token
    abort "Usage: import.rb <asana_export.json> <conduit-token>"
  end

  # Iterate over each asana task
  tasks = JSON.load(IO.read(ASANA_EXPORT_FILE))['data']
  progress = MiniProgress.new tasks.length

  all_users = get_users
  tasks.each do |task|
    migrate_asana_task task, nil, nil, all_users
    progress.next
  end

  puts "\n\nDone."

end
