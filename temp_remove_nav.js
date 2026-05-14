const fs = require('fs');
const path = require('path');
const dir = path.join(__dirname, 'views', 'teacher');
const files = fs.readdirSync(dir).filter(f => f.endsWith('.html'));
let count = 0;
for (const file of files) {
  const filepath = path.join(dir, file);
  let content = fs.readFileSync(filepath, 'utf8');
  
  const inboxRegex = /^\s*<a href="\/teacher\/inbox"[^>]*>.*?Escalated Inbox.*?<\/a>\r?\n/m;
  const gradeRegex = /^\s*<a href="\/teacher\/grades"[^>]*>.*?Gradebook.*?<\/a>\r?\n/m;
  
  let modified = false;
  if (inboxRegex.test(content)) {
    content = content.replace(inboxRegex, '');
    modified = true;
  }
  if (gradeRegex.test(content)) {
    content = content.replace(gradeRegex, '');
    modified = true;
  }
  
  if (modified) {
    fs.writeFileSync(filepath, content);
    console.log('Updated ' + file);
    count++;
  }
}
console.log('Total files updated: ' + count);
