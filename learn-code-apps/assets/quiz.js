// Shared quiz widget. Usage in a lesson:
//   <div class="quiz"><script type="application/json">[{"stem":"…","options":["…"],"answer":0,"why":"…"}]</script></div>
//   <script src="../assets/quiz.js"></script>
// Immediate feedback per question; running score at the end of each quiz block.
document.querySelectorAll('.quiz').forEach((quiz) => {
  const data = JSON.parse(quiz.querySelector('script[type="application/json"]').textContent);
  let answered = 0;
  let right = 0;
  const score = document.createElement('p');
  score.className = 'score';

  data.forEach((item, qi) => {
    const q = document.createElement('div');
    q.className = 'q';
    const stem = document.createElement('p');
    stem.className = 'stem';
    stem.textContent = `${qi + 1}. ${item.stem}`;
    q.appendChild(stem);

    const why = document.createElement('p');
    why.className = 'why';
    why.textContent = item.why;

    item.options.forEach((text, oi) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'opt';
      btn.textContent = text;
      btn.addEventListener('click', () => {
        q.querySelectorAll('button.opt').forEach((b) => (b.disabled = true));
        q.querySelectorAll('button.opt')[item.answer].classList.add('correct');
        if (oi === item.answer) right += 1;
        else btn.classList.add('wrong');
        why.style.display = 'block';
        answered += 1;
        if (answered === data.length) score.textContent = `Score: ${right} / ${data.length} — retrieval done. Wrong answers are the valuable ones: reread just those sections, then move on.`;
      });
      q.appendChild(btn);
    });

    q.appendChild(why);
    quiz.appendChild(q);
  });
  quiz.appendChild(score);
});
