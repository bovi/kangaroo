#!/usr/bin/env ruby

require 'webrick'

# acquire a new question
# only for `klass`
def get_question(csv, klass)
  questions = []
  File.open(csv).each do |line|
    # skip header line
    next if line =~ /Lang/

    t = line.chomp.split(',')

    # skip lines that don't match the selected class
    next if t[1] != klass

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
SOLUTIONS = File.expand_path(File.join(File.dirname(__FILE__), 'solutions.csv'))
RESULTS = File.expand_path(File.join(File.dirname(__FILE__), 'results.csv'))
KLASS = '34'
server = WEBrick::HTTPServer.new :Port => 8080

# define webapp
server.mount_proc '/' do |req, res|
  lang, klass, year, task = get_question(SOLUTIONS, KLASS)
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
  File.open('results.csv', 'a') do |f|
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
server.mount '/exams', WEBrick::HTTPServlet::FileHandler, 'exams'

trap 'INT' do server.shutdown end

server.start
