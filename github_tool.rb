require 'octokit'
require 'highline/import'
require 'yaml'

def print_newline
  puts
end

def bold str
  "<%=color('#{str}', :bold) %>"
end

def indent str
  "   #{str}"
end

class GithubTool
  class NoOrgsFoundError < StandardError; end

  def initialize
    @username = ''
    @password = ''
  end

  def run
   GithubTool.login_to_github

   begin
     $client.user
     print_newline
     say "#{bold 'Logging into GitHub...Success'}"
   rescue => e
     print_newline
     say "<%= color('ERROR', BOLD) %>: Failed to log into GitHub"
     say e.message
     return
   end

   begin
     load_orgs
     show_orgs @orgs
   rescue GithubTool::NoOrgsFoundError
     print_newline
     say "<%= color('ERROR', BOLD) %>: No org names are found in settings.yml"
     return
   end

   loop do
    print_newline
    print_newline
    choose do |menu|
      menu.header = "*** Available commands ***"
      menu.prompt = "What do you want to do? orgs/add/remove/show/compare/quit"
      menu.choice(:orgs, 'show the orgs') { show_orgs @orgs }
      menu.choice(:add, 'add a member to a team to all orgs') { add_team_member }
      menu.choice(:remove, 'remove a member from a team from all orgs') { remove_team_member }
      menu.choice(:show, 'show members in a team in each org') { show_team_members }
      menu.choice(:compare, 'compare team members in each org') { compare_team_members }
      menu.choice(:quit, 'exit program') { exit }
    end
   end
  end

  def add_team_member
    print_newline

    say "#{bold 'Add member to a team in all orgs'}"
    @member = ask('who to add> ') { |u| u.echo = true}
    @team_name = ask('which team> ') { |u| u.echo = true}

    lookup_github_user(@member)
    return unless prompt_for_yes_or_no("is '#{bold @member}' the correct user")

    load_orgs.each do |org_name|
      print_newline
      say "Checking org '#{bold org_name}'..."
      begin
        organization_teams = $client.organization_teams(org_name)
        team_found = organization_teams.select do |t|
          t.name == @team_name
        end.first


        unless team_found
          say "team '#{bold @team_name}' not found in org '#{bold org_name}'...Skipped"
          next
        end

        if prompt_for_yes_or_no("add #{bold @member} to #{bold @team_name}  ")
          response = $client.add_team_member(team_found.id, @member)

          say "adding '#{bold @member}' to team '#{bold @team_name}' in org '#{bold org_name}'...#{response ? 'Success' : 'Failed'}"
        end

      rescue Octokit::Forbidden
        say "<%= color('ERROR', BOLD) %>: not permitted to access org '#{bold org_name}'"
      rescue => e
        puts e.class
        puts e
      end
    end
  end

  def remove_team_member
    print_newline

    say "#{bold 'Remove member from a team in all orgs'}"
    @member = ask('who to remove> ') { |u| u.echo = true}
    @team_name = ask('which team> ') { |u| u.echo = true}

    lookup_github_user(@member)
    return unless prompt_for_yes_or_no("is '#{bold @member}' the correct user")

    load_orgs.each do |org_name|
      print_newline
      say "Checking org '#{bold org_name}'..."
      begin
        organization_teams = $client.organization_teams(org_name)
        team_found = organization_teams.select do |t|
          t.name == @team_name
        end.first

        unless team_found
          say "team '#{bold @team_name}' not found in org '#{bold org_name}'...Skipped"
          next
        end

        if prompt_for_yes_or_no("remove #{bold @member} from #{bold @team_name}  ")
          response = $client.remove_team_member(team_found.id, @member)

          say "removing '#{bold @member}' from team '#{bold @team_name}' in org '#{bold org_name}'...#{response ? 'Success' : 'Failed'}"
        end

      rescue Octokit::Forbidden
        say "<%= color('ERROR', BOLD) %>: not permitted to access org '#{bold org_name}'"
      rescue => e
        puts e.class
        puts e
      end
    end
  end

  def show_team_members
    print_newline

    say "#{bold 'List members of a team in each org'}"
    team_name = ask('which team> ') { |u| u.echo = true}

    load_orgs.each do |org_name|
      print_newline
      say "Checking org '#{bold org_name}'..."
      begin
        organization_teams = $client.organization_teams(org_name)
        team_found = organization_teams.select do |t|
          t.name == team_name
        end.first

        unless team_found
          say "team '#{bold team_name}' not found in org '#{bold org_name}'...Skipped"
          next
        end

        members = $client.team_members(team_found.id)
        say "team '#{bold team_name}' has #{members.count} members:"
        members.map(&:login).each { |str| say indent str}

      rescue Octokit::Forbidden
        say "<%= color('ERROR', BOLD) %>: not permitted to access org '#{bold org_name}'"
      rescue => e
        puts e.class
        puts e
      end

    end
  end

  def compare_team_members
    print_newline
    say "#{bold 'Compare members of a team between the orgs'}"

    say 'Not supported yet!'
  end

  def load_orgs
    settings = YAML.load_file('settings.yml')
    @orgs = settings.fetch('orgs')

    if @orgs.nil?
      raise GithubTool::NoOrgsFoundError
    end

    @orgs = @orgs.split
  end

  def prompt_for_yes_or_no(question)
    loop do
      answer = ask("#{question.rstrip} [y/n]? ")
      case answer[0].strip
      when 'y'
        return true
      when 'n'
        return false
      else

      end
    end
  end

  private

  def lookup_github_user(username)
    begin
      user = $client.user(username)
      print_newline
      say "User '#{bold username}' is found on GitHub"
      say "#{bold username}'s avatar: '#{bold user.avatar_url}"
    rescue Octokit::NotFound
      say "<%= color('ERROR', BOLD) %>: user '#{bold username}' is not a valid github user"
    end

  end

  def show_orgs(orgs)
    print_newline

    mesg = "Found #{orgs.count} orgs:"
    say "#{bold mesg}"
    orgs.each { |org| say indent org}
  end


  def self.login_to_github
    print_newline
    say 'GitHub login'
    @username = ask('admin username> ') { |u| u.echo = true}
    @password = ask('admin password> ') { |p| p.echo = '*'}

    $client = Octokit::Client.new(login: @username, password: @password)
  end


end

GithubTool.new.run
