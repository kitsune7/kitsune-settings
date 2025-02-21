export default function (plop) {
  const targetPath = plop.getDestBasePath() || plop.getArg('target-path');
  plop.setDestBasePath(targetPath);

  // Rest of your plopfile code
}
