# ./overwatch: any zsh VS Code opens in this workspace (including terminals it revives after a
# restart) becomes the live feed. ZDOTDIR points here via .vscode/settings.json.
# Exception: the "Plain shell" terminal profile sets OVERWATCH_PLAIN=1 and gets your normal zsh.
if [[ -n $OVERWATCH_PLAIN ]]; then
  ZDOTDIR=$HOME
  [[ -f $HOME/.zshenv ]] && source $HOME/.zshenv
  [[ -o login && -f $HOME/.zprofile ]] && source $HOME/.zprofile
  [[ -f $HOME/.zshrc ]] && source $HOME/.zshrc
  [[ -o login && -f $HOME/.zlogin ]] && source $HOME/.zlogin
else
  exec /bin/zsh "${CLAUDE_LIVE_WS:-$PWD}/.vscode/claude-live.zsh"
fi
