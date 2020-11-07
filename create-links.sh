#!/bin/bash

ln -sf ~/dotfiles/nvim ~/.config/nvim
ln -sf ~/dotfiles/.oh-my-zsh ~/.oh-my-zsh
ln -sf ~/dotfiles/.zsh-syntax-highlighting ~/.zsh-syntax-highlighting
ln -sf ~/dotfiles/.zshrc ~/.zshrc

cd ~/dotfiles

git submodule update --init


