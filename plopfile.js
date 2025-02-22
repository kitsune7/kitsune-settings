export default function (plop) {
  const settingsDir = process.env.SETTINGS_DIR || './';
  plop.setGenerator('new-zsh-file', {
    description: 'Make a new zsh file in kitsune-settings/oh-my-zsh-custom',
    prompts: [
      {
        type: 'input',
        name: 'name',
        message: 'What should it be named (without the extension)?',
      },
    ],
    actions: [
      {
        type: 'add',
        path: `${settingsDir}/oh-my-zsh-custom/{{name}}.zsh`,
        templateFile: 'plop-templates/zsh-file.hbs',
      },
    ],
  });
}
