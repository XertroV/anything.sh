import React from 'react';

export const EXIT_MESSAGES = [
  <>Press <span className="text-zinc-300">CTRL+C</span> to archive the specimen.</>,
  <><span className="text-zinc-300">CTRL+C</span>: the slime understands.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span> before it gets ideas.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span> to induce dormancy.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span>. It's been expecting you.</>,
  <><span className="text-zinc-300">CTRL+C</span> returns it to the jar. For now.</>,
  <>The organism responds well to <span className="text-zinc-300">CTRL+C</span>.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span> to fossilize this session.</>,
  <><span className="text-zinc-300">CTRL+C</span>: a mercy, really.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span> while you still can.</>,
  <>The slime will remember this. <span className="text-zinc-300">CTRL+C</span> to exit.</>,
  <><span className="text-zinc-300">CTRL+C</span> triggers sporulation. Don't worry about it.</>,
  <>Press <span className="text-zinc-300">CTRL+C</span>. The slime is grateful.</>,
  <>When satisfied, press <span className="text-zinc-300">CTRL+C</span>. Or when afraid.</>,
  <><span className="text-zinc-300">CTRL+C</span> to halt the pulsing.</>,
];

export const getRandomExitMessage = () =>
  EXIT_MESSAGES[Math.floor(Math.random() * EXIT_MESSAGES.length)];
