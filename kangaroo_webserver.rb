#!/usr/bin/env ruby

require 'webrick'
require 'set'

def get_results(csv)
  results = {}

  unless File.exists? csv
    return results
  end

  File.open(csv, 'r:UTF-8').each do |line|
    next if line =~ /Lang/
    time, lang, klass, year, task, answer,
      reference_answer, correct, duration = line.chomp.split(',')
    
    # Skip if time is not a valid number
    next unless time =~ /^\d+$/

    key = "#{lang}_#{klass}_#{year}_#{task}"
    if results.has_key? key
      ratio = correct == 'true' ? 1 : -1
      ok = results[key][:ok]
      ko = results[key][:ko]
      # Only include duration if it's not -1 (not from an exam)
      durations = results[key][:durations]
      durations << duration if duration != '-1'
      
      results[key] = {
        times: results[key][:times] + 1,
        durations: durations,
        ratio: results[key][:ratio] + ratio,
        ok: correct == 'true' ? ok+1 : ok,
        ko: correct == 'true' ? ko : ko+1,
        time: time
      }
    else
      ratio = correct == 'true' ? 1 : -1
      # Only include duration if it's not -1 (not from an exam)
      durations = duration == '-1' ? [] : [duration]
      results[key] = {
        times: 1,
        durations: durations,
        ratio: ratio,
        ok: correct == 'true' ? 1 : 0,
        ko: correct == 'true' ? 0 : 1,
        time: time
      }
    end
  end

  results
end

# acquire a new question
# only for `klass`
def get_question(csv_solutions, csv_results, klass, id)
  questions = []
  asked_questions = get_results(csv_results).keys.to_set
  
  # Get available questions
  File.open(csv_solutions, 'r:UTF-8').each do |line|
    next if line =~ /Lang/
    t = line.chomp.split(',')

    # skip lines that don't match the selected class
    key = "#{t[0]}_#{t[1]}_#{t[2]}_#{t[3]}"
    
    if id.nil?
      # For random questions, filter by class and unasked only
      next if t[1] != klass
      questions << line.chomp.split(',') unless asked_questions.include?(key)
    else
      # For specific question requests, only filter by id
      questions << line.chomp.split(',') if key == id
    end
  end
  
  puts "Available new questions for class #{klass}: #{questions.size}" if id.nil?
  
  # If all questions have been asked (and no specific id was requested), reset and use all questions
  if questions.empty? && id.nil?
    File.open(csv_solutions, 'r:UTF-8').each do |line|
      next if line =~ /Lang/
      t = line.chomp.split(',')
      next if t[1] != klass
      questions << line.chomp.split(',')
    end
  end

  questions.sample
end

# get the correct solution for a specific question
def get_solution(lang, klass, year, question_no, csv)
  # open csv file and find answer
  File.open(csv, 'r:UTF-8').each do |line|
    next if line =~ /Lang/
    next unless line =~ /#{lang},#{klass},#{year},#{question_no},/
    return line.chomp.split(',')[4]
  end
end

# count the questions answered today
def get_todays_answers(csv)
  today = 0

  File.open(csv, 'r:UTF-8').each do |line|
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

def format_time(timestamp)
  diff = Time.now.to_i - timestamp

  case diff
  when 0...(60*60)
    'less than 1 hour ago'
  when (60*60)...(60*60*24)
    'less than 1 day ago'
  when (60*60*24)...(60*60*24*7)
    "#{(diff / 60 / 60 / 24).to_i} days ago"
  else
    "#{(diff / 60 / 60 / 24 / 7).to_i} weeks ago"
  end
end

def get_exam_questions(csv_solutions, klass, year = nil)
  questions_by_year = {}
  
  File.open(csv_solutions, 'r:UTF-8').each do |line|
    next if line =~ /Lang/
    t = line.chomp.split(',')
    next if t[1] != klass
    
    question_year = t[2]
    questions_by_year[question_year] ||= []
    questions_by_year[question_year] << t
  end
  
  # If year is provided, use it; otherwise choose random year
  selected_year = year || questions_by_year.keys.sample
  return questions_by_year[selected_year], selected_year
end

# absolute from current directory
SOLUTIONS = File.expand_path(File.join(File.dirname(__FILE__), 'solutions.csv'))
RESULTS = File.expand_path(File.join(File.dirname(__FILE__), 'results.csv'))
EXAMS = File.expand_path(File.join(File.dirname(__FILE__), 'exams'))
EXAM_RESULTS = File.expand_path(File.join(File.dirname(__FILE__), 'exam_results.csv'))
KLASS = '34'
FILTER_ALTER_ASKED = false
FILTER_EASY_QUESTIONS = true
server = WEBrick::HTTPServer.new :Port => 8080

# index
server.mount_proc '/' do |req, res|
  res.body = <<HTML
<html>
  <head>
    <title>Kangaroo</title>
    <style>
      .container {
        max-width: 1000px;
        margin: 0 auto;
        padding: 20px;
      }
      h1, h2 {
        text-align: center;
        color: #333;
      }
      .menu-section {
        margin: 30px 0;
        background: #f9f9f9;
        padding: 20px;
        border-radius: 10px;
      }
      .menu-list {
        list-style: none;
        padding: 0;
      }
      .menu-item {
        margin: 15px 0;
        font-size: 1.5em;
      }
      .menu-link {
        display: block;
        padding: 10px 20px;
        background: white;
        color: #333;
        text-decoration: none;
        border-radius: 5px;
        border: 1px solid #ddd;
        transition: all 0.2s ease;
      }
      .menu-link:hover {
        background: #f0f0f0;
        transform: translateX(10px);
        color: blue;
      }
      .stats-link {
        background: #f0f0f0;
        font-weight: bold;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>Aaron's Kangaroo Test Center</h1>
      
      <div class="menu-section">
        <h2>Practice Mode</h2>
        <ul class="menu-list">
          <li class="menu-item"><a href="/question?class=34" class="menu-link">Practice for Class 3 and 4</a></li>
          <li class="menu-item"><a href="/question?class=56" class="menu-link">Practice for Class 5 and 6</a></li>
          <li class="menu-item"><a href="/question?class=78" class="menu-link">Practice for Class 7 and 8</a></li>
          <li class="menu-item"><a href="/question?class=910" class="menu-link">Practice for Class 9 and 10</a></li>
          <li class="menu-item"><a href="/question?class=1113" class="menu-link">Practice for Class 11 and 13</a></li>
          <li class="menu-item"><a href="/stats" class="menu-link stats-link">Question Statistics</a></li>
        </ul>
      </div>
      
      <div class="menu-section">
        <h2>Exam Mode</h2>
        <ul class="menu-list">
          <li class="menu-item"><a href="/exam?class=34" class="menu-link">Full Exam for Class 3 and 4</a></li>
          <li class="menu-item"><a href="/exam?class=56" class="menu-link">Full Exam for Class 5 and 6</a></li>
          <li class="menu-item"><a href="/exam?class=78" class="menu-link">Full Exam for Class 7 and 8</a></li>
          <li class="menu-item"><a href="/exam?class=910" class="menu-link">Full Exam for Class 9 and 10</a></li>
          <li class="menu-item"><a href="/exam?class=1113" class="menu-link">Full Exam for Class 11 and 13</a></li>
          <li class="menu-item"><a href="/exam_stats" class="menu-link stats-link">Exam Statistics</a></li>
        </ul>
      </div>
    </div>
  </body>
</html>
HTML
end

# statistics
server.mount_proc '/stats' do |req, res|
  sort_by = case req.query['by']
            when 'ratio' then :ratio
            when 'times' then :times
            when 'durations' then :durations
            when 'class' then :class
            when 'ok' then :ok
            when 'ko' then :ko
            when 'time' then :time
            else :time
            end

  results = get_results(RESULTS)
  
  # Handle empty results
  total_questions_answered = if results.empty?
    0
  else
    results.to_a.inject{|s,n|r=s[1][:times]+n[1][:times]; [nil, {times:r}]}[1][:times]
  end

  # Calculate summary statistics
  if results.any?
    total_unique = results.size
    total_correct = results.sum { |_, v| v[:ok] }
    total_wrong = results.sum { |_, v| v[:ko] }
    avg_success = (total_correct.to_f / (total_correct + total_wrong) * 100).round(1)
    
    summary = <<HTML
<div style="text-align: center; margin: 20px 0;">
  <h2>Summary</h2>
  <p>Total Unique Questions: #{total_unique}</p>
  <p>Total Questions Answered: #{total_questions_answered}</p>
  <p>Correct Answers: #{total_correct}</p>
  <p>Wrong Answers: #{total_wrong}</p>
  <p>Average Success Rate: #{avg_success}%</p>
</div>
HTML
  else
    summary = "<p style='text-align: center;'>No questions answered yet.</p>"
  end

  table = "<table border='1'>"
  table << <<HTML
<tr>
  <th>Question</th>
  <th><a href="/stats?by=class">Class</a></th>
  <th><a href="/stats?by=times">Tries</a></th>
  <th><a href="/stats?by=ok">Correct</a></th>
  <th><a href="/stats?by=ko">Wrong</a></th>
  <th><a href="/stats?by=ratio">Success Rate</a></th>
  <th><a href="/stats?by=durations">Average Duration</a></th>
  <th><a href="/stats?by=time">Last Answered</a></th>
</tr>
HTML

  unless results.empty?
    r_sorted = case sort_by
               when :durations then 
                 results.sort_by do |i,j| 
                   valid_durations = j[:durations].reject(&:empty?)
                   if valid_durations.empty?
                     -1  # Put entries with no valid durations at the end
                   else
                     valid_durations.map(&:to_i).sum / valid_durations.size
                   end
                 end.reverse
               when :class
                 results.sort_by do |i,j|
                   lang, klass, year, question = i.split('_')
                   case klass
                   when '34' then 1
                   when '56' then 2
                   when '78' then 3
                   when '910' then 4
                   when '1113' then 5
                   else 9
                   end
                 end.reverse
               when :ratio then results.sort_by{|i,j| j[sort_by].to_i}
               else results.sort_by{|i,j| j[sort_by].to_i}.reverse
               end
    r_sorted.each do |key, value|
      id = key
      lang, klass, year, question = key.split('_')
      times = value[:times]
      ratio = value[:ratio]
      ok = value[:ok]
      ko = value[:ko]
      last_time_answered = format_time(value[:time].to_i)
      success_rate = ((ok.to_f / (ok + ko)) * 100).round(1)
      
      # Handle durations array - only consider non-exam answers
      valid_durations = value[:durations].reject(&:empty?)
      duration = if valid_durations.empty?
        "N/A"
      else
        "#{valid_durations.map(&:to_i).sum / valid_durations.size}sec"
      end
      
      success_color = if success_rate >= 70
        "#62ff33"  # Green for good performance
      elsif success_rate >= 40
        "#ffd700"  # Gold for medium performance
      else
        "#ff4444"  # Red for poor performance
      end
      
      table << <<HTML
<tr>
  <td><a href='/question?id=#{key}' style="text-decoration: none; color: blue;">#{id}</a></td>
  <td>#{klass}</td>
  <td>#{times}</td>
  <td style="color: #62ff33;">#{ok}</td>
  <td style="color: #ff4444;">#{ko}</td>
  <td style="color: #{success_color};">#{success_rate}%</td>
  <td>#{duration}</td>
  <td>#{last_time_answered}</td>
</tr>
HTML
    end
  end
  table << "</table>"

  res.body = <<HTML
<html>
  <head>
    <title>Question Statistics</title>
    <style>
      .container {
        max-width: 1200px;
        margin: 0 auto;
        padding: 20px;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        margin: 20px 0;
      }
      th, td {
        padding: 10px;
        text-align: center;
        border: 1px solid #ddd;
      }
      th {
        background-color: #f0f0f0;
      }
      th a {
        text-decoration: none;
        color: #333;
      }
      th a:hover {
        color: blue;
      }
      tr:nth-child(even) {
        background-color: #f9f9f9;
      }
      tr:hover {
        background-color: #f5f5f5;
      }
      .nav {
        text-align: center;
        margin-bottom: 20px;
      }
      .nav a {
        margin: 0 10px;
        text-decoration: none;
        color: blue;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="nav">
        <a href="/">Home</a> |
        <a href="/stats">Question Statistics</a> |
        <a href="/exam_stats">Exam Statistics</a>
      </div>
      
      <h1 style="text-align: center;">Question Statistics</h1>
      
      #{summary}
      #{table}
    </div>
  </body>
</html>
HTML
end

# define webapp
server.mount_proc '/question' do |req, res|
  klass = req.query['class']
  id = req.query['id']
  lang, klass, year, task = get_question(SOLUTIONS, RESULTS, klass, id)
  answers_today = get_todays_answers(RESULTS)
  
  res.body = <<~HTML
    <html>
      <head>
        <title>Question</title>
        <style>
          .container {
            max-width: 1000px;
            margin: 0 auto;
            padding: 20px;
          }
          .nav {
            text-align: center;
            margin-bottom: 20px;
          }
          .nav a {
            margin: 0 10px;
            text-decoration: none;
            color: blue;
          }
          .question-container {
            text-align: center;
            margin: 20px 0;
          }
          .question-title {
            color: blue;
            font-size: 2em;
            margin-bottom: 20px;
          }
          .question-image {
            margin: 20px 0;
          }
          .answer-section {
            margin: 30px 0;
          }
          input[type='radio'] {
            -webkit-appearance: none;
            width: 50px;
            height: 50px;
            background: white;
            border-radius: 5px;
            border: 2px solid #555;
            margin: 0 5px 0 25px;
            cursor: pointer;
            transition: all 0.2s ease;
          }
          input[type='radio']:checked {
            background: blue;
            border-color: blue;
          }
          input[type='radio']:hover {
            border-color: blue;
          }
          .answer-label {
            font-size: 2em;
            margin: 0 25px 0 5px;
          }
          .submit-button {
            font-size: 1.5em;
            padding: 10px 30px;
            background-color: blue;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.2s ease;
          }
          .submit-button:disabled {
            background-color: #cccccc;
            cursor: not-allowed;
          }
          .submit-button:hover:not(:disabled) {
            background-color: darkblue;
          }
          .stats {
            background-color: #f0f0f0;
            padding: 10px;
            border-radius: 5px;
            margin: 10px 0;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="nav">
            <a href="/">Home</a> |
            <a href="/stats">Question Statistics</a> |
            <a href="/exam_stats">Exam Statistics</a>
            <div class="stats">
              Questions solved in the last 24 hours: #{answers_today}
            </div>
          </div>
          
          <div class="question-container">
            <div class="question-title">
              <b>Question</b>
            </div>
            
            <div class="question-image">
              <img src="/exams/#{lang}/#{klass}/#{year}/#{task}.png" style="width: 75%; max-width: 800px;" />
            </div>
            
            <div class="answer-section">
              <form id="form" action="/answer" method="post">
                <div>
                  <input type="radio" name="answer" value="A" id="answerA" />
                  <label for="answerA" class="answer-label">A</label>
                  
                  <input type="radio" name="answer" value="B" id="answerB" />
                  <label for="answerB" class="answer-label">B</label>
                  
                  <input type="radio" name="answer" value="C" id="answerC" />
                  <label for="answerC" class="answer-label">C</label>
                  
                  <input type="radio" name="answer" value="D" id="answerD" />
                  <label for="answerD" class="answer-label">D</label>
                  
                  <input type="radio" name="answer" value="E" id="answerE" />
                  <label for="answerE" class="answer-label">E</label>
                </div>
                
                <input type="hidden" name="lang" value="#{lang}" />
                <input type="hidden" name="klass" value="#{klass}" />
                <input type="hidden" name="year" value="#{year}" />
                <input type="hidden" name="task" value="#{task}" />
                <input type="hidden" name="time" value="#{Time.now.to_i}" />
                
                <div style="margin-top: 30px;">
                  <input type="submit" value="Submit Answer" class="submit-button" disabled />
                </div>
              </form>
            </div>
          </div>
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
              getRadioValue('answer');
          });

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

  l = "#{Time.now.to_i},#{lang},#{klass},#{year},#{task},#{answer}," +
       "#{reference_answer},#{correct},#{duration}"
  File.open(RESULTS, 'a') do |f|
    f.puts l
  end

  res.body = <<~HTML
    <html>
      <head>
        <title>#{correct ? 'Correct' : 'Wrong'}</title>
        <style>
          .container {
            max-width: 1000px;
            margin: 0 auto;
            padding: 20px;
          }
          .nav {
            text-align: center;
            margin-bottom: 20px;
          }
          .nav a {
            margin: 0 10px;
            text-decoration: none;
            color: blue;
          }
          .result {
            font-size: 3em;
            text-align: center;
            margin: 20px 0;
            font-weight: bold;
          }
          .answer-details {
            text-align: center;
            font-size: 1.5em;
            margin: 20px 0;
            color: blue;
          }
          .question-image {
            text-align: center;
            margin: 20px 0;
          }
          .next-button {
            display: inline-block;
            font-size: 1.2em;
            text-decoration: none;
            color: white;
            background-color: blue;
            padding: 10px 20px;
            border-radius: 5px;
            font-weight: bold;
            transition: background-color 0.2s ease;
          }
          .next-button:hover {
            background-color: darkblue;
          }
          .button-container {
            text-align: center;
            margin: 20px 0;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="nav">
            <a href="/">Home</a> |
            <a href="/stats">Question Statistics</a> |
            <a href="/exam_stats">Exam Statistics</a>
          </div>
          
          <div class="result" style="color: #{correct ? '#62ff33' : '#f23939'}">
            #{correct ? 'Correct!' : 'Wrong'}
            #{correct ? '' : "(you selected: #{answer})"}
          </div>
          
          <div class="answer-details">
            Correct Answer is <b>#{reference_answer}</b>
          </div>
          
          <div class="question-image">
            <img src="/exams/#{lang}/#{klass}/#{year}/#{task}.png" style="width: 75%; max-width: 800px;" />
          </div>
          
          <div class="button-container">
            <a href="/question?class=#{klass}" class="next-button">
              Next Question
            </a>
          </div>
        </div>
      </body>
    </html>
  HTML
end

# mount image folder
server.mount '/exams', WEBrick::HTTPServlet::FileHandler, EXAMS

# Exam mode - initial page
server.mount_proc '/exam' do |req, res|
  klass = req.query['class']
  questions, selected_year = get_exam_questions(SOLUTIONS, klass)
  start_time = Time.now.to_i
  
  questions_html = questions.map do |q|
    lang, klass, year, task = q
    <<~HTML
      <div style="margin: 20px 0; padding: 20px; border: 1px solid #ccc;">
        <img src="/exams/#{lang}/#{klass}/#{year}/#{task}.png" style="width: 75%;" />
        <br/>
        <div style="font-size: 1.5em; margin-top: 10px;">
          Your Answer: 
          <input type="radio" name="answer_#{task}" value="A" id="answer_#{task}_A" />
          <label for="answer_#{task}_A" class="answer-label">A</label>
          
          <input type="radio" name="answer_#{task}" value="B" id="answer_#{task}_B" />
          <label for="answer_#{task}_B" class="answer-label">B</label>
          
          <input type="radio" name="answer_#{task}" value="C" id="answer_#{task}_C" />
          <label for="answer_#{task}_C" class="answer-label">C</label>
          
          <input type="radio" name="answer_#{task}" value="D" id="answer_#{task}_D" />
          <label for="answer_#{task}_D" class="answer-label">D</label>
          
          <input type="radio" name="answer_#{task}" value="E" id="answer_#{task}_E" />
          <label for="answer_#{task}_E" class="answer-label">E</label>
        </div>
      </div>
    HTML
  end.join("\n")
  
  res.body = <<~HTML
    <html>
      <head>
        <title>Exam Mode</title>
        <style>
          .exam-container {
            max-width: 1000px;
            margin: 0 auto;
            padding: 20px;
          }
          .header {
            position: sticky;
            top: 0;
            background: white;
            padding: 10px;
            border-bottom: 2px solid #ccc;
            margin-bottom: 20px;
            z-index: 100;
          }
          .nav {
            text-align: center;
            margin-bottom: 20px;
          }
          .nav a {
            margin: 0 10px;
            text-decoration: none;
            color: blue;
          }
          input[type='radio'] {
            -webkit-appearance: none;
            width: 50px;
            height: 50px;
            background: white;
            border-radius: 5px;
            border: 2px solid #555;
            margin: 0 5px 0 25px;
            cursor: pointer;
            transition: all 0.2s ease;
          }
          input[type='radio']:checked {
            background: blue;
            border-color: blue;
          }
          input[type='radio']:hover {
            border-color: blue;
          }
          .answer-label {
            font-size: 2em;
            margin: 0 25px 0 5px;
          }
          .submit-button {
            font-size: 1.5em;
            padding: 10px 30px;
            background-color: #ff4444;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.2s ease;
          }
          .submit-button:hover {
            background-color: #ff2222;
          }
          .countdown {
            font-size: 1.5em;
            margin: 10px 0;
            font-weight: bold;
          }
          .countdown.warning {
            color: #ff4444;
            animation: blink 1s infinite;
          }
          @keyframes blink {
            50% { opacity: 0.5; }
          }
        </style>
      </head>
      <body>
        <div class="exam-container">
          <div class="nav">
            <a href="/">Home</a> |
            <a href="/stats">Question Statistics</a> |
            <a href="/exam_stats">Exam Statistics</a>
          </div>
          
          <div class="header">
            <h1>Exam Mode - Class #{klass} (Year #{selected_year})</h1>
            <p>Started at: #{Time.now.strftime('%H:%M:%S')}</p>
            <div class="countdown" id="countdown">Time remaining: 90:00</div>
          </div>
          
          <form action="/exam/results" method="post" id="examForm">
            <input type="hidden" name="class" value="#{klass}" />
            <input type="hidden" name="year" value="#{selected_year}" />
            <input type="hidden" name="start_time" value="#{start_time}" />
            
            #{questions_html}
            
            <div style="text-align: center; margin: 20px 0;">
              <input type="submit" value="Finish Exam" class="submit-button" />
            </div>
          </form>
        </div>

        <script>
          // Set the countdown time (90 minutes = 5400 seconds)
          let timeLeft = 5400;
          
          function updateCountdown() {
            const minutes = Math.floor(timeLeft / 60);
            const seconds = timeLeft % 60;
            const display = `Time remaining: ${minutes}:${seconds.toString().padStart(2, '0')}`;
            
            const countdownElement = document.getElementById('countdown');
            countdownElement.textContent = display;
            
            // Add warning class when less than 5 minutes remain
            if (timeLeft <= 300) {
              countdownElement.classList.add('warning');
            }
            
            // Auto-submit when time runs out
            if (timeLeft <= 0) {
              window.onbeforeunload = null;  // Remove the leave warning
              document.getElementById('examForm').submit();
              return;
            }
            
            timeLeft--;
            setTimeout(updateCountdown, 1000);
          }
          
          // Start the countdown
          updateCountdown();
          
          // Warn before leaving page
          window.onbeforeunload = function() {
            return "Are you sure you want to leave? Your exam progress will be lost!";
          };
          
          // Remove warning when submitting form
          document.getElementById('examForm').onsubmit = function() {
            window.onbeforeunload = null;
          };
        </script>
      </body>
    </html>
  HTML
end

# Exam mode - show results
server.mount_proc '/exam/results' do |req, res|
  if req.request_method == 'POST'
    klass = req.query['class']
    year = req.query['year']
    start_time = req.query['start_time'].to_i
    duration = Time.now.to_i - start_time
    
    questions, _ = get_exam_questions(SOLUTIONS, klass, year)
    correct_count = 0
    
    results_html = questions.map do |q|
      lang, klass, year, task = q
      answer = req.query["answer_#{task}"]
      reference_answer = get_solution(lang, klass, year, task, SOLUTIONS).upcase
      correct = answer&.upcase == reference_answer.upcase
      correct_count += 1 if correct
      
      # Record each answer in results.csv with duration -1 to mark it as part of an exam
      l = "#{Time.now.to_i},#{lang},#{klass},#{year},#{task},#{answer}," +
          "#{reference_answer},#{correct},-1"
      File.open(RESULTS, 'a') do |f|
        f.puts l
      end
      
      result_color = correct ? "#62ff33" : "#f23939"
      result_text = correct ? "Correct" : "Wrong"
      
      <<~HTML
        <div style="margin: 20px 0; padding: 10px; border: 1px solid #ccc;">
          <div style="font-size: 1.5em;">
            <span style="color: #{result_color}">Question #{task}: #{result_text}</span>
            <br/>
            Your Answer: #{answer || 'Not answered'} | Correct Answer: #{reference_answer}
          </div>
          <div style="margin-top: 10px;">
            <img src="/exams/#{lang}/#{klass}/#{year}/#{task}.png" style="width: 75%;" />
          </div>
        </div>
      HTML
    end.join("\n")
    
    # Record the exam summary in exam_results.csv
    # Format: timestamp,class,year,duration_minutes,correct_count,total_questions
    exam_line = "#{Time.now.to_i},#{klass},#{year},#{duration / 60}," +
                "#{correct_count},#{questions.size}"
    
    File.open(EXAM_RESULTS, 'a') do |f|
      f.puts exam_line
    end
    
    total_minutes = duration / 60
    
    res.body = <<~HTML
      <html>
        <head>
          <title>Exam Results</title>
          <style>
            .container {
              max-width: 1000px;
              margin: 0 auto;
              padding: 20px;
            }
            .nav {
              text-align: center;
              margin-bottom: 20px;
            }
            .nav a {
              margin: 0 10px;
              text-decoration: none;
              color: blue;
            }
            .results-summary {
              font-size: 1.5em;
              margin: 20px 0;
              background: #f9f9f9;
              padding: 20px;
              border-radius: 10px;
            }
            h1 {
              text-align: center;
              color: #333;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="nav">
              <a href="/">Home</a> |
              <a href="/stats">Question Statistics</a> |
              <a href="/exam_stats">Exam Statistics</a>
            </div>
            
            <h1>Exam Results</h1>
            <div class="results-summary">
              <p>Time taken: #{total_minutes} minutes</p>
              <p>Score: #{correct_count}/#{questions.size} (#{(correct_count.to_f / questions.size * 100).round(1)}%)</p>
            </div>
            
            <div style="margin-top: 30px;">
              #{results_html}
            </div>
          </div>
        </body>
      </html>
    HTML
  end
end

# Add this helper method near the other helpers
def get_exam_stats(csv)
  exams = []
  
  return exams unless File.exists? csv
  
  File.open(csv, 'r:UTF-8').each do |line|
    next if line =~ /timestamp/  # Skip header if exists
    timestamp, klass, year, duration, correct, total = line.chomp.split(',')
    
    exams << {
      timestamp: timestamp.to_i,
      klass: klass,
      year: year,
      duration: duration.to_i,
      correct: correct.to_i,
      total: total.to_i
    }
  end
  
  exams
end

# Add new route for exam statistics
server.mount_proc '/exam_stats' do |req, res|
  exams = get_exam_stats(EXAM_RESULTS)
  
  # Sort by timestamp descending (most recent first)
  exams.sort_by! { |exam| -exam[:timestamp] }
  
  table = "<table border='1' style='margin-left: auto; margin-right: auto'>"
  table << <<HTML
<tr>
  <th>Date</th>
  <th>Class</th>
  <th>Year</th>
  <th>Duration</th>
  <th>Score</th>
  <th>Percentage</th>
</tr>
HTML

  exams.each do |exam|
    date = Time.at(exam[:timestamp]).strftime('%Y-%m-%d %H:%M')
    percentage = (exam[:correct].to_f / exam[:total] * 100).round(1)
    
    table << <<HTML
<tr>
  <td>#{date}</td>
  <td>#{exam[:klass]}</td>
  <td>#{exam[:year]}</td>
  <td>#{exam[:duration]} minutes</td>
  <td>#{exam[:correct]}/#{exam[:total]}</td>
  <td>#{percentage}%</td>
</tr>
HTML
  end
  
  table << "</table>"
  
  # Calculate some summary statistics
  if exams.any?
    avg_score = (exams.sum { |e| e[:correct].to_f / e[:total] } / exams.size * 100).round(1)
    avg_duration = (exams.sum { |e| e[:duration] } / exams.size).round(1)
    total_exams = exams.size
    
    summary = <<HTML
<div style="text-align: center; margin: 20px 0;">
  <h2>Summary</h2>
  <p>Total Exams Taken: #{total_exams}</p>
  <p>Average Score: #{avg_score}%</p>
  <p>Average Duration: #{avg_duration} minutes</p>
</div>
HTML
  else
    summary = "<p style='text-align: center;'>No exams taken yet.</p>"
  end

  res.body = <<HTML
<html>
  <head>
    <title>Exam Statistics</title>
    <style>
      .container {
        max-width: 1000px;
        margin: 0 auto;
        padding: 20px;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        margin: 20px 0;
      }
      th, td {
        padding: 10px;
        text-align: center;
      }
      th {
        background-color: #f0f0f0;
      }
      .nav {
        text-align: center;
        margin-bottom: 20px;
      }
      .nav a {
        margin: 0 10px;
        text-decoration: none;
        color: blue;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="nav">
        <a href="/">Home</a> |
        <a href="/stats">Question Statistics</a> |
        <a href="/exam_stats">Exam Statistics</a>
      </div>
      
      <h1 style="text-align: center;">Exam Statistics</h1>
      
      #{summary}
      #{table}
    </div>
  </body>
</html>
HTML
end

trap 'INT' do server.shutdown end

server.start
