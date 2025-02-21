export default function (plop) {
  const targetPath = plop.getDestBasePath() || plop.getArg('target-path');
  console.log('targetPath:', targetPath);
  console.log('destBasePath:', plop.getDestBasePath());

  plop.setActionType('debug', function (answers, config, plop) {
    console.log(answers);
    console.log(config);
    console.log(plop.getPlopfilePath());
  });

  plop.setGenerator('new-plop', {
    description: 'Create a new plop file',
    prompts: [
      {
        type: 'input',
        name: 'name',
        message: 'What is your plop file name?',
      },
    ],
    actions: [
      {
        type: 'debug',
        path: './',
      },
    ],
  });
}
