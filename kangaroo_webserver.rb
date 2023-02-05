#!/usr/bin/env ruby

require 'webrick'

def get_results(csv)
  results = {}

  unless File.exists? csv
    return results
  end

  File.open(csv).each do |line|
    next if line =~ /Lang/
    time, lang, klass, year, task, answer,
      reference_answer, correct,duration = line.chomp.split(',')

    key = "#{lang}_#{klass}_#{year}_#{task}"
    if results.has_key? key
      ratio = correct == 'true' ? 1 : -1
      results[key] = {
        times: results[key][:times] + 1,
        durations: results[key][:durations] << duration,
        ratio: results[key][:ratio] + ratio
      }
    else
      ratio = correct == 'true' ? 1 : -1
      results[key] = {
        times: 1,
        durations: [duration],
        ratio: ratio
      }
    end
  end

  results
end

# acquire a new question
# only for `klass`
def get_question(csv_solutions, csv_results, klass, skip_if_asked, skip_if_easy)
  questions = []
  results = get_results(csv_results)
  File.open(csv_solutions).each do |line|
    # skip header line
    next if line =~ /Lang/

    t = line.chomp.split(',')

    # skip lines that don't match the selected class
    next if t[1] != klass
    key = "#{t[0]}_#{t[1]}_#{t[2]}_#{t[3]}"

    if results.has_key? key
      # skip if already asked
      next if skip_if_asked

      # skip if already answered correctly
      if skip_if_easy
        next if results[key][:ratio] > 0
      end
    end

    questions << line.chomp.split(',')
  end

  questions.sample
end

# get the correct solution for a specific question
def get_solution(lang, klass, year, question_no, csv)
  # open csv file and find answer
  File.open(csv).each do |line|
    next if line =~ /Lang/
    next unless line =~ /#{lang},#{klass},#{year},#{question_no},/
    return line.chomp.split(',')[4]
  end
end

# count the questions answered today
def get_todays_answers(csv)
  today = 0

  File.open(csv).each do |line|
    next if line =~ /Lang/
    time = line.chomp.split(',')[0]
    # if the answer was given less than 16h ago
    # we assume it was done today
    if ((Time.now.to_i - time.to_i) / 60 / 60) < 16
      today += 1
    end
  end

  return today
end

# absolute from current directory
SOLUTIONS = File.expand_path(File.join(File.dirname(__FILE__), '..', 'var', 'kangaroo', 'solutions.csv'))
RESULTS = File.expand_path(File.join(File.dirname(__FILE__), '..', 'var', 'kangaroo', 'results.csv'))
EXAMS = File.expand_path(File.join(File.dirname(__FILE__), '..', 'var', 'kangaroo', 'exams'))
KLASS = '34'
FILTER_ALTER_ASKED = false
FILTER_EASY_QUESTIONS = true
server = WEBrick::HTTPServer.new :Port => 8080

server.mount_proc '/stats' do |req, res|
  results = get_results(RESULTS)

  table = "<table border='1'>"
  table << "<tr><th>Question</th><th>Tries</th><th>Ratio</th><th>Average Duration</th></tr>"
  r_sorted = results.sort_by{|i,j| j[:ratio].to_i}
  r_sorted.each do |key, value|
    id = key
    lang, klass, year, question = key.split('_')
    times = value[:times]
    ratio = value[:ratio]
    duration = value[:durations].map {|i| i.to_i}.sum / value[:durations].size
    table << "<tr><td><a href='/exams/#{lang}/#{klass}/#{year}/#{question}.PNG'>#{id}</a></td>"
    table << "<td>#{times}</td><td>#{ratio}</td><td>#{duration}</td></tr>"
  end
  table << "</table>"
  total_questions_answered = results.to_a.inject{|s,n|r=s[1][:times]+n[1][:times]; [nil, {times:r}]}
  total_questions_answered = total_questions_answered[1][:times]
  res.body = <<HTML
<html>
<body>
<div>Total unique questions answered: #{results.size}</div>
<br />
<div>Total questions answered: #{total_questions_answered}</div>
<br />
#{table}
</body>
</html>
HTML
end

# define webapp
server.mount_proc '/' do |req, res|
  lang, klass, year, task = get_question(SOLUTIONS, RESULTS, KLASS, FILTER_ALTER_ASKED, FILTER_EASY_QUESTIONS)
  answers_today = get_todays_answers(RESULTS)
  # increase size of a checkbox in HTML
  res.body = <<~HTML
<html>
<head>
<title>Question</title>
</head>
<style>
input[type='radio'] {
    -webkit-appearance:none;
    width:50px;
    height:50px;
    background:white;
    border-radius:5px;
    border:2px solid #555;
}
input[type='radio']:checked {
    background: blue;
}
</style>
<body>
<div>Solved in the last 24 hours: #{answers_today}</div>
<div style="text-align:center; color: blue; font-size: 4em"><b>Question</b></div>
<br />
<div style="text-align: center; font-size: 3em;">

<img src="/exams/#{lang}/#{klass}/#{year}/#{task}.PNG" style="width: 75%;" />
</div>
<br />
<br />
<div style="text-align: center; font-size: 3em;">
<form id="form" action="/answer" method="post">
<input type="radio" name="answer" value="A" /> A &nbsp;&nbsp;&nbsp;
<input type="radio" name="answer" value="B" /> B &nbsp;&nbsp;&nbsp;
<input type="radio" name="answer" value="C" /> C &nbsp;&nbsp;&nbsp;
<input type="radio" name="answer" value="D" /> D &nbsp;&nbsp;&nbsp;
<input type="radio" name="answer" value="E" /> E
<input type="hidden" name="lang" value="#{lang}" />
<input type="hidden" name="klass" value="#{klass}" />
<input type="hidden" name="year" value="#{year}" />
<input type="hidden" name="task" value="#{task}" />
<input type="hidden" name="time" value="#{Time.now.to_i}" />
<br /><br />
<input style="font-size: 1em" type="submit" value="Submit" disabled />
</form>
</div>
<script>
const getRadioValue = (name) => {
  const radios = document.getElementsByName(name);
  let val;   
  Object.keys(radios).forEach((obj, i) => {
    if (radios[i].checked) {
      val = radios[i].value;
    }
  });
  var btn = document.querySelector('[type=submit]');
  btn.disabled = false;
  return val;
} 

document.getElementById('form').addEventListener('change', (e) => {
    getRadioValue('answer'); // value of checked radio button.
});

// disable button after first click
document.getElementById('form').addEventListener('submit', (e) => {
  var btn = document.querySelector('[type=submit]');
  btn.disabled = true;
});
</script>
</body>
</html>
HTML
end

# define /answer webapp
# this is called when the user submits the answer
# it checks if the answer is correct
# and sends the result to the server
server.mount_proc '/answer' do |req, res|
  lang = req.query['lang']
  klass = req.query['klass']
  year = req.query['year']
  task = req.query['task']
  answer = req.query['answer'].upcase
  time = req.query['time']

  duration = Time.now.to_i - time.to_i

  reference_answer = get_solution(lang, klass, year, task, SOLUTIONS).upcase
  correct = answer.upcase == reference_answer.upcase

  l = "#{Time.now.to_i},#{lang},#{klass},#{year},#{task},#{answer},#{reference_answer},#{correct},#{duration}"
  File.open(RESULTS, 'a') do |f|
    f.puts l
  end

  # return if answer is correct
  result = if correct
    <<HTML
<title>Correct</title>
</head>
<body>
<div style="font-size: 5em; text-align: center; color: #62ff33;"><b>Correct</b></div>
HTML
  else
    <<HTML
<title>Wrong</title>
</head>
<body>
<div style="font-size: 5em; text-align: center; color: #f23939;"><b>Wrong</b>
(you selected: #{answer.upcase})</div>
HTML
  end
  # format image to be always 100% width
  res.body = <<~HTML
<html>
<head>
#{result}
<br />
<div style="text-align: center; font-size: 3em;">
<span style="color: blue">Correct Answer is <b>#{reference_answer.to_s.upcase}</b>
for this question:</span>
<br />
<br />
<img src="/exams/#{lang}/#{klass}/#{year}/#{task}.PNG" style="width: 75%;" />
<br />
<br />
<!-- make a link to the next question which looks like a button -->
<a href="/" style="font-size: 1em; text-decoration: none; color: white; background-color: blue; padding: 10px; border-radius: 5px; font-weight: bold">Next Question</a>
</div>
</body>
</html>
HTML
end

# mount image folder
server.mount '/exams', WEBrick::HTTPServlet::FileHandler, EXAMS

trap 'INT' do server.shutdown end

server.start
